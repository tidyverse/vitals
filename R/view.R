#' Interactively view local evaluation logs
#'
#' @description
#' vitals bundles the Inspect log viewer, an interactive app for exploring
#' evaluation logs. Supply a path to a directory of tasks written to json.
#' For individual [Task] objects, use the `$view()` method instead.
#'
#' @param dir Path to a directory containing task eval logs.
#' @param host Host to serve on. Defaults to "127.0.0.1".
#' @param port Port to serve on. If NULL, will find a random available port.
#'
#' @inherit Task examples
#' @return The server object (invisibly)
#' @export
vitals_view <- function(
  dir = vitals_log_dir(),
  host = "127.0.0.1",
  port = NULL
) {
  vitals_view_impl(dir = dir, host = host, port = port)
}

vitals_view_impl <- function(
  dir = vitals_log_dir(),
  host = "127.0.0.1",
  port = NULL,
  call = caller_env()
) {
  dist_dir <- system.file("dist", package = "vitals")

  if (is.null(port)) {
    port <- httpuv::randomPort()
  }

  tryCatch(
    {
      existing_server <- httpuv::listServers()
      if (length(existing_server) > 0) {
        httpuv::stopServer(existing_server[[1]])
      }
    },
    error = function(cnd) {
      cli::cli_abort(
        "Unable to terminate the existing server.",
        parent = cnd,
        call = call
      )
    }
  )

  if (!dir.exists(dir)) {
    cli::cli_abort(
      "Log directory {.file {dir}} not found.",
      call = call
    )
  }

  server <- httpuv::startServer(
    host = host,
    port = port,

    app = list(
      call = function(req) {
        tryCatch(
          {
            # parse query parameters
            query <- parse_query_string(req$QUERY_STRING)

            # handle API routes first
            if (startsWith(req$PATH_INFO, "/api/")) {
              # handle dynamic route first
              if (startsWith(req$PATH_INFO, "/api/logs/")) {
                file <- substr(req$PATH_INFO, 11, nchar(req$PATH_INFO))
                file <- utils::URLdecode(file)
                return(get_api_log_file(dir, file, query))
              }

              # handle static routes
              return(switch(
                req$PATH_INFO,
                "/api/logs" = get_api_logs(dir),
                "/api/log-dir" = get_api_log_dir(dir),
                "/api/log-files" = get_api_log_files(dir),
                "/api/log-headers" = get_api_log_headers(dir, query),
                "/api/events" = get_api_events(),
                "/api/eval-set" = get_api_eval_set(),
                "/api/flow" = get_api_flow(),
                list(status = 404, body = "API endpoint not found")
              ))
            }

            # then handle static files
            if (req$PATH_INFO == "/" || !grepl("\\.", req$PATH_INFO)) {
              # serve index.html for root or routes without file extensions
              index_path <- file.path(dist_dir, "index.html")
              return(list(
                status = 200,
                headers = list(
                  'Content-Type' = 'text/html',
                  'Cache-Control' = 'no-cache'
                ),
                body = readBin(index_path, "raw", file.info(index_path)$size)
              ))
            } else {
              # serve static files from dist
              file_path <- file.path(dist_dir, substring(req$PATH_INFO, 2))
              if (file.exists(file_path)) {
                content_type <- switch(
                  tools::file_ext(file_path),
                  "html" = "text/html",
                  "js" = "application/javascript",
                  "css" = "text/css",
                  "svg" = "image/svg+xml",
                  "application/octet-stream"
                )
                return(list(
                  status = 200,
                  headers = list(
                    'Content-Type' = content_type,
                    'Cache-Control' = 'no-cache'
                  ),
                  body = readBin(file_path, "raw", file.info(file_path)$size)
                ))
              }
            }

            list(status = 404, body = "Not found")
          },
          error = function(e) {
            # log the error for debugging
            message("Error processing request: ", e$message)
            list(
              status = 500,
              headers = list('Content-Type' = 'text/plain'),
              body = paste("Error:", e$message)
            )
          }
        )
      }
    )
  )

  url <- sprintf("http://%s:%d", host, port)
  cli::cli_inform(
    c("v" = "Inspect Viewer running at: {.url {url}}"),
    class = "vitals_viewer_start"
  )

  if (interactive() && !is_testing()) {
    utils::browseURL(url)
  }

  invisible(server)
}

parse_query_string <- function(query_string) {
  if (is.null(query_string) || query_string == "") {
    return(list())
  }

  # Remove leading ? if present
  query_string <- sub("^\\?", "", query_string)

  # Replace any ?file= with &file= (except at the start)
  query_string <- gsub("\\?file=", "&file=", query_string)

  parts <- strsplit(query_string, "&")[[1]]
  params <- lapply(parts, function(p) {
    kv <- strsplit(p, "=")[[1]]
    if (length(kv) == 2) {
      val <- utils::URLdecode(kv[2])
      res <- list(val)
      names(res) <- kv[1]
      return(res)
    }
    NULL
  })
  do.call(c, params)
}

path_to_file_url <- function(path) {
  normalized <- normalizePath(path, winslash = "/", mustWork = FALSE)
  if (.Platform$OS.type == "windows") {
    paste0("file:///", normalized)
  } else {
    paste0("file://", normalized)
  }
}

get_log_files_metadata <- function(dir) {
  files <- list.files(dir, pattern = "\\.json$", recursive = TRUE)
  files <- files[basename(files) != "listing.json"]
  files <- sort(files, decreasing = TRUE)

  lapply(files, function(f) {
    file_path <- file.path(dir, f)
    info <- file.info(file_path)

    task_info <- tryCatch(
      {
        headers <- eval_log_read_headers(file_path)
        list(
          task = headers$eval$task,
          task_id = headers$eval$task_id
        )
      },
      error = function(e) {
        list(task = NULL, task_id = NULL)
      }
    )

    list(
      name = path_to_file_url(file_path),
      size = info$size,
      mtime = as.numeric(info$mtime) * 1000,
      task = task_info$task,
      task_id = task_info$task_id
    )
  })
}

json_response <- function(data, status = 200) {
  list(
    status = status,
    headers = list(
      'Content-Type' = 'application/json',
      'Cache-Control' = 'no-cache'
    ),
    body = jsonlite::toJSON(
      data,
      auto_unbox = TRUE,
      null = "null"
    )
  )
}

get_api_logs <- function(dir) {
  resp <- list(
    log_dir = path_to_file_url(dir),
    files = get_log_files_metadata(dir)
  )
  json_response(resp)
}

get_api_log_dir <- function(dir) {
  resp <- list(
    log_dir = path_to_file_url(dir)
  )
  json_response(resp)
}

get_api_log_files <- function(dir) {
  resp <- list(
    response_type = "full",
    files = get_log_files_metadata(dir)
  )
  json_response(resp)
}

get_api_log_headers <- function(dir, query) {
  if (!is.null(query$file)) {
    files <- as.list(query)

    headers <- lapply(files, function(f) {
      if (startsWith(f, "file://")) {
        file_path <- substr(f, 8, nchar(f))
      } else if (startsWith(f, "/") || grepl("^[A-Za-z]:", f)) {
        file_path <- f
      } else {
        file_path <- file.path(dir, f)
      }

      if (file.exists(file_path)) {
        content <- eval_log_read_headers(file_path)
      } else {
        NULL
      }
    })

    names(headers) <- NULL
    return(json_response(headers))
  }

  json_response(list())
}

get_api_events <- function() {
  json_response(list())
}

get_api_eval_set <- function() {
  json_response(NULL)
}

get_api_flow <- function() {
  json_response(NULL)
}

get_api_log_file <- function(dir, file, query) {
  if (startsWith(file, "file://")) {
    file_path <- substr(file, 8, nchar(file))
  } else if (startsWith(file, "/") || grepl("^[A-Za-z]:", file)) {
    file_path <- file
  } else {
    file_path <- file.path(dir, file)
  }

  if (!file.exists(file_path)) {
    return(list(status = 404, body = "File not found"))
  }

  content <- jsonlite::fromJSON(file_path)

  header_only <- query$`header-only`
  if (!is.null(header_only)) {
    header_only <- as.numeric(header_only)
    file_size_mb <- file.info(file_path)$size / (1024 * 1024)

    if (!is.na(header_only) && file_size_mb > header_only) {
      if (
        !is.null(content$records) &&
          length(content$records) > 10
      ) {
        content$records <- head(content$records, 10)
      }
    }
  }

  json_response(content)
}
