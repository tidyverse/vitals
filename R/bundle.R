#' Prepare logs for deployment
#'
#' @description
#' This function creates a standalone bundle of the Inspect viewer with log files
#' that can be deployed statically. It copies the UI viewer files, log files, and
#' generates the necessary configuration files.
#'
#' @param log_dir Path to the directory containing log files. Defaults to
#' `vitals_log_dir()`.
#' @param output_dir Path to the directory where the bundled output will be placed.
#' @param overwrite Whether to overwrite an existing output directory. Defaults to FALSE.
#'
#' @section Deployment:
#'
#' This function generates a directory that's ready for deployment to any
#' static web server such as GitHub Pages, S3 buckets, or Netlify. If you
#' have a connection to Posit Connect configured, you can deploy a directory
#' of log files with the following:
#'
#' ```r
#' tmp_dir <- withr::local_tempdir()
#' vitals_bundle(output_dir = tmp_dir, overwrite = TRUE)
#' rsconnect::deployApp(tmp_dir)
#' ```
#'
#' @return Invisibly returns the output directory path. That directory contains:
#'
#' ```
#' output_dir
#' |-- index.html
#' |-- robots.txt
#' |-- assets
#'     |--  ..
#' |-- logs
#'     |--  ..
#' ```
#'
#' `robots.txt` prevents crawlers from indexing the viewer. That said, many
#' crawlers only read the `robots.txt` at the root directory of a package, so
#' the file will likely be ignored if this folder isn't the root directory of
#' the deployed page. `assets/` is the bundled source for the viewer. `logs/`
#' is the `log_dir` as well as a `listing.json`, which is a manifest file for the
#' directory.
#'
#' @examples
#' if (!identical(Sys.getenv("ANTHROPIC_API_KEY"), "")) {
#'   # set the log directory to a temporary directory
#'   withr::local_envvar(VITALS_LOG_DIR = withr::local_tempdir())
#'
#'   library(ellmer)
#'   library(tibble)
#'
#'   simple_addition <- tibble(
#'     input = c("What's 2+2?", "What's 2+3?"),
#'     target = c("4", "5")
#'   )
#'
#'   tsk <- Task$new(
#'     dataset = simple_addition,
#'     solver = generate(chat_anthropic(model = "claude-3-7-sonnet-latest")),
#'     scorer = model_graded_qa()
#'   )
#'
#'   tsk$eval()
#'
#'   output_dir <- tempdir()
#'   vitals_bundle(output_dir = output_dir, overwrite = TRUE)
#' }
#'
#' @export
vitals_bundle <- function(
  log_dir = vitals_log_dir(),
  output_dir = NULL,
  overwrite = FALSE
) {
  if (!dir.exists(log_dir)) {
    cli::cli_abort(
      "{.arg log_dir} {.file {log_dir}} doesn't exist."
    )
  }
  check_string(output_dir)

  if (dir.exists(output_dir) && !overwrite) {
    cli::cli_abort(c(
      "'{.arg output_dir}' already exists.",
      "i" = "Choose another output directory or use overwrite = TRUE."
    ))
  }

  working_dir <- withr::local_tempdir()

  dist_dir <- system.file("dist", package = "vitals")
  copy_dir_contents(dist_dir, working_dir)

  log_dir_name <- "logs"
  view_logs_dir <- file.path(working_dir, log_dir_name)
  dir.create(view_logs_dir, recursive = TRUE, showWarnings = FALSE)

  copy_log_files(log_dir, view_logs_dir)

  write_log_dir_manifest(view_logs_dir)

  inject_configuration(file.path(working_dir, "index.html"), log_dir_name)
  write_robots_txt(working_dir)

  move_output(working_dir, output_dir)

  cli::cli_alert_success("Bundle {.file {output_dir}} created!")
  invisible(output_dir)
}

copy_dir_contents <- function(source_dir, dest_dir) {
  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
  }

  files <- list.files(
    source_dir,
    recursive = TRUE,
    all.files = TRUE,
    include.dirs = FALSE
  )

  for (file in files) {
    src_file <- file.path(source_dir, file)
    dest_file <- file.path(dest_dir, file)

    parent_dir <- dirname(dest_file)
    if (!dir.exists(parent_dir)) {
      dir.create(parent_dir, recursive = TRUE, showWarnings = FALSE)
    }

    file.copy(src_file, dest_file, overwrite = TRUE)
  }
}

copy_log_files <- function(log_dir, target_dir, call = caller_env()) {
  if (!dir.exists(log_dir)) {
    cli::cli_abort("The log directory {.file {log_dir}} doesn't exist.")
  }

  log_files <- list.files(
    log_dir,
    pattern = "\\.json$",
    full.names = TRUE,
    recursive = TRUE
  )

  if (length(log_files) == 0) {
    cli::cli_abort(
      "The log directory {.file {log_dir}} doesn't contain any JSON log files.",
      call = call
    )
  }

  for (file in log_files) {
    rel_path <- sub(
      paste0("^", gsub("([.\\])", "\\\\\\1", normalizePath(log_dir))),
      "",
      normalizePath(file)
    )
    rel_path <- sub("^[/\\\\]", "", rel_path)

    dest_file <- file.path(target_dir, rel_path)
    dest_dir <- dirname(dest_file)

    if (!dir.exists(dest_dir)) {
      dir.create(dest_dir, recursive = TRUE, showWarnings = FALSE)
    }

    file.copy(file, dest_file, overwrite = TRUE)
  }
}

write_log_dir_manifest <- function(log_dir) {
  manifest_file <- file.path(log_dir, "listing.json")

  log_files <- list.files(
    log_dir,
    pattern = "\\.json$",
    recursive = TRUE,
    full.names = TRUE
  )
  log_files <- setdiff(log_files, file.path(log_dir, "listing.json"))

  manifest <- lapply(log_files, eval_log_read_headers)
  manifest <- setNames(manifest, basename(log_files))

  jsonlite::write_json(
    manifest,
    manifest_file,
    auto_unbox = TRUE,
    pretty = TRUE
  )
}

inject_configuration <- function(html_file, log_dir) {
  content <- readLines(html_file, warn = FALSE)

  config_data <- list(
    log_dir = log_dir,
    web_path = ".",
    deployment_type = "static",
    version = "1.0"
  )

  # Convert to JSON string and properly escape for HTML embedding
  config_json <- jsonlite::toJSON(config_data, auto_unbox = TRUE)
  log_dir_script <- sprintf(
    '  <script id="log_dir_context" type="application/json">%s</script>',
    config_json
  )

  head_close_pos <- grep("</head>", content, fixed = TRUE)[1]
  if (!is.na(head_close_pos)) {
    content <- c(
      content[1:(head_close_pos - 1)],
      log_dir_script,
      content[head_close_pos:length(content)]
    )
  }

  writeLines(content, html_file)
}

write_robots_txt <- function(dir) {
  file_path <- file.path(dir, "robots.txt")
  content <- "User-agent: *\nDisallow: /\n"
  writeLines(content, file_path)
}

move_output <- function(from_dir, to_dir) {
  if (dir.exists(to_dir)) {
    unlink(to_dir, recursive = TRUE)
  }

  dir.create(to_dir, recursive = TRUE, showWarnings = FALSE)

  copy_dir_contents(from_dir, to_dir)
}
