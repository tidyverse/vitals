# validating log files (for dev use only) --------------------------------------
# invokes Inspect's pydantic models on an eval log file so that
# we can ensure we're writing files that are compatible with the
# viewer.
# first-time setup (optional) (requires Python >=3.10):
#   reticulate::install_python(version = '3.14.0')
#   # restart R session
#   reticulate::virtualenv_create(envname = "vitals-venv")
#   reticulate::py_install("inspect_ai", envname = "vitals-venv")
python_cmd <- function() {
  if (!is_installed("reticulate")) {
    return("python3")
  }
  if (reticulate::py_available()) {
    return(reticulate::py_config()$python)
  }
  reticulate::py_require(c("inspect-ai", "pydantic"))
  tryCatch(
    reticulate::py_config()$python,
    error = function(e) "python3"
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
      paste0(
        c("The generated log did not pass the pydantic model: ", result),
        collapse = "\n"
      )
    )
  }
})
