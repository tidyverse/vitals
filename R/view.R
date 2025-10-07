#' Interactively view local evaluation logs
#'
#' @description
#' vitals bundles the Inspect log viewer, an interactive app for exploring
#' evaluation logs. Supply a path to a directory of tasks written to json.
#' For individual [Task] objects, use the `$view()` method instead.
#'
#' @param dir Path to a directory containing task eval logs.
#' @param host Host to serve on. Defaults to "127.0.0.1".
#' @param port Port to serve on. Defaults to 7576, one greater than the Python
#' implementation.
#'
#' @inherit Task examples
#' @return The server object (invisibly)
#' @export
vitals_view <- function(
  dir = vitals_log_dir(),
  host = "127.0.0.1",
  port = 7576
) {
  vitals_view_impl(dir = dir, host = host, port = port)
}

vitals_view_impl <- function(
  dir = vitals_log_dir(),
  host = "127.0.0.1",
  port = 7576,
  call = caller_env()
) {
  dist_dir <- system.file("dist", package = "vitals")

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
              # GET /api/logs
              if (req$PATH_INFO == "/api/logs") {
                files <- list.files(dir, pattern = "\\.json$", recursive = TRUE)
                files <- files[basename(files) != "listing.json"]
                files <- sort(files, decreasing = TRUE)
                log_files <- lapply(files, function(f) {
                  file_path <- file.path(dir, f)
                  info <- file.info(file_path)

                  list(
                    name = f,
                    size = info$size,
                    mtime = as.numeric(info$mtime) * 1000
                  )
                })

                resp <- list(
                  dir = normalizePath(dir),
                  files = log_files
                )

                return(list(
                  status = 200,
                  headers = list(
                    'Content-Type' = 'application/json',
                    'Cache-Control' = 'no-cache'
                  ),
                  body = jsonlite::toJSON(
                    resp,
                    auto_unbox = TRUE,
                    null = "null"
                  )
                ))
              }

              # GET /api/log-headers
              log_headers <- list(
                status = 200,
                headers = list(
                  'Content-Type' = 'application/json',
                  'Cache-Control' = 'no-cache'
                )
              )
              if (req$PATH_INFO == "/api/log-headers") {
                if (!is.null(query$file)) {
                  files <- as.list(query)

                  headers <- lapply(files, function(f) {
                    file_path <- file.path(dir, f)
                    if (file.exists(file_path)) {
                      content <- eval_log_read_headers(file_path)
                    } else {
                      NULL
                    }
                  })

                  names(headers) <- NULL
                  log_headers$body <-
                    jsonlite::toJSON(headers, auto_unbox = TRUE, null = "null")
                  return(log_headers)
                }

                log_headers$body <-
                  jsonlite::toJSON(list(), auto_unbox = TRUE, null = "null")
                return(log_headers)
              }

              # GET /api/logs/{filename}
              if (startsWith(req$PATH_INFO, "/api/logs/")) {
                file <- substr(req$PATH_INFO, 11, nchar(req$PATH_INFO))
                file <- utils::URLdecode(file)
                file_path <- file.path(dir, file)

                if (file.exists(file_path)) {
                  # read the file content first
                  content <- jsonlite::fromJSON(file_path)

                  # check header_only parameter
                  header_only <- query$`header-only`
                  if (!is.null(header_only)) {
                    header_only <- as.numeric(header_only)
                    file_size_mb <- file.info(file_path)$size / (1024 * 1024)

                    if (!is.na(header_only) && file_size_mb > header_only) {
                      # include only metadata and first few records
                      if (
                        !is.null(content$records) &&
                          length(content$records) > 10
                      ) {
                        content$records <- head(content$records, 10)
                      }
                    }
                  }

                  return(list(
                    status = 200,
                    headers = list(
                      'Content-Type' = 'application/json',
                      'Cache-Control' = 'no-cache'
                    ),
                    body = jsonlite::toJSON(
                      content,
                      auto_unbox = TRUE,
                      null = "null"
                    )
                  ))
                }

                return(list(status = 404, body = "File not found"))
              }

              return(list(status = 404, body = "API endpoint not found"))
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
