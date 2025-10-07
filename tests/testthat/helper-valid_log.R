# validating log files (for dev use only) --------------------------------------
# invokes Inspect's pydantic models on an eval log file so that
# we can ensure we're writing files that are compatible with the
# viewer.
python_cmd <- function() {
  if (!is_installed("reticulate")) {
    return("python")
  }
  tryCatch(
    {
      eval_bare(call2("use_virtualenv", "vitals-venv", .ns = "reticulate"))
      eval_bare(call2("py_config", .ns = "reticulate"))$python
    },
    error = function(e) "python"
  )
}

expect_valid_log <- local({
  .pydantic_skip_status <- if (
    !interactive() && !isTRUE(as.logical(Sys.getenv("NOT_CRAN", "false")))
  ) {
    "On CRAN."
  } else if (
    system2(python_cmd(), "--version", stdout = FALSE, stderr = FALSE) != 0
  ) {
    "Python is not available"
  } else if (
    system2(
      python_cmd(),
      "-c 'import inspect_ai'",
      stdout = FALSE,
      stderr = FALSE
    ) !=
      0
  ) {
    "inspect_ai Python module is not available"
  } else if (
    system2(
      python_cmd(),
      "-c 'import pydantic'",
      stdout = FALSE,
      stderr = FALSE
    ) !=
      0
  ) {
    "pydantic Python module is not available"
  } else if (
    !file.exists(system.file("test/validate_log.py", package = "vitals"))
  ) {
    "Python validation script not found."
  } else {
    NULL
  }

  function(x) {
    if (!is.null(.pydantic_skip_status)) {
      skip(.pydantic_skip_status)
    }

    if (!file.exists(x)) {
      skip(paste0("Log file ", x, " does not exist."))
    }

    result <- system2(
      python_cmd(),
      args = c(system.file("test/validate_log.py", package = "vitals"), x),
      stdout = TRUE,
      stderr = TRUE
    )

    status <- attr(result, "status")

    expect(
      is.null(status) || status == 0,
      formatted_pydantic_error(result)
    )
  }
})

formatted_pydantic_error <- function(result) {
  # "inst/test/inspect/logs/2025-03-24T10-39-36-05-00_simple-arithmetic_fQ9mYnqZFhtEuUenPpJgKL.json"
  if (length(result) == 1) {
    formatted_message <- cli::format_message(c(
      "The generated log did not pass the pydantic model:",
      glue::glue("{{.field {result[1]}}}")
    ))
  } else {
    # Make the result more readable by removing redundant elements
    # and formatting indices with cli (#159)
    result <- result[!grepl("For further information visit", result)]
    result_length <- length(result)
    field_positions <- seq(2, result_length, by = 2)

    for (pos in field_positions) {
      result[pos] <- glue::glue("{{.field {result[pos]}}}")
    }

    result_with_breaks <- result[1]
    for (i in seq(2, length(result), by = 2)) {
      result_with_breaks <- c(result_with_breaks, "", result[i:(i + 1)])
    }

    formatted_message <- cli::format_message(c(
      "The generated log did not pass the pydantic model:",
      "",
      result_with_breaks
    ))
  }
}
