#' The log directory
#'
#' @description
#' vitals supports the `VITALS_LOG_DIR` environment variable,
#' which sets a default directory to write logs to in [Task]'s `$eval()`
#' and `$log()` methods.
#'
#' @param dir A directory to configure the environment variable
#' `VITALS_LOG_DIR` to.
#'
#' @returns
#' Both `vitals_log_dir()` and `vitals_log_dir_set()` return the current
#' value of the environment variable `VITALS_LOG_DIR`. `vitals_log_dir_set()`
#' additionally sets it to a new value.
#'
#' To set this variable in every new R session, you might consider adding it
#' to your `.Rprofile`, perhaps with `usethis::edit_r_profile()`.
#'
#' @examples
#' vitals_log_dir()
#'
#' dir <- tempdir()
#'
#' vitals_log_dir_set(dir)
#'
#' vitals_log_dir()
#' @export
vitals_log_dir <- function() {
  Sys.getenv("VITALS_LOG_DIR", unset = NA)
}

#' @rdname vitals_log_dir
#' @export
vitals_log_dir_set <- function(dir) {
  old <- Sys.getenv("VITALS_LOG_DIR", unset = NA)
  Sys.setenv(VITALS_LOG_DIR = dir)
  invisible(old)
}

# Read and write evaluation logs
#
# @description
# Utilities for reading and writing evaluation logs.
#
# These utilities support the `VITALS_LOG_DIR` environment variable,
# which sets a default directory to write logs to.
#
# @param x For `eval_log_read()`, a path to the log file to read. For
# For `eval_log_write()`, an evaluation log object to write to disk.
# @param dir Directory where logs should be stored.
#
# @examples
# file <-
#   system.file(
#     "logs/2025-02-08T15-51-00-06-00_simple-arithmetic_o3cKtmsvqQtmXGZhvfDrKB.json",
#      package = "vitals"
#   )
#
# example_eval_log <- eval_log_read(file)
#
# example_eval_log
# @name eval_log
eval_log_read <- function(x) {
  structure(jsonlite::read_json(x), class = c("eval_log", "list"))
}

# @rdname eval_log
eval_log_write <- function(x = eval_log(), dir = vitals_log_dir()) {
  if (!dir.exists(dir)) {
    dir.create(dir, showWarnings = FALSE, recursive = TRUE)
  }

  path <- file.path(dir, eval_log_filename(x))
  jsonlite::write_json(
    x = structure(x, class = "list"),
    path = path,
    auto_unbox = TRUE,
    pretty = TRUE
  )
  path
}

# eval log files are quite relational, where the `samples` field takes up the
# most storage by far. every header field we need precedes the top-level
# `samples` key in the written JSON (see eval_log()), so read only the leading
# bytes up to that key rather than parsing the whole file. (#26)
header_fields <-
  c("version", "status", "eval", "plan", "results", "stats")

eval_log_read_headers <- function(x) {
  header_json <- read_log_header_json(x)
  if (is.null(header_json)) {
    res_fields <- jsonlite::fromJSON(x, simplifyVector = FALSE)[header_fields]
    return(jsonlite::fromJSON(jsonlite::toJSON(res_fields, auto_unbox = TRUE)))
  }

  jsonlite::fromJSON(header_json)[header_fields]
}

read_log_header_json <- function(x, cap = 1048576L) {
  con <- file(x, "rb")
  on.exit(close(con))

  buffer <- ""
  repeat {
    chunk <- readChar(con, 65536L, useBytes = TRUE)
    if (length(chunk) == 0L || !nzchar(chunk)) {
      return(NULL)
    }
    buffer <- paste0(buffer, chunk)

    at <- regexpr('\n  "samples"', buffer, fixed = TRUE)
    if (at > 0L) {
      header <- sub(",[[:space:]]*$", "", substr(buffer, 1L, at - 1L))
      return(paste0(header, "\n}"))
    }

    if (nchar(buffer, type = "bytes") > cap) {
      return(NULL)
    }
  }
}
