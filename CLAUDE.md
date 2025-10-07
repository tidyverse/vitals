You are situated inside of an R package source directory. The subdirectory `R/` contains source files. The subdirectory `tests/testthat/` contains corresponding tests. e.g. `R/task.R` is tested primarily in `tests/testthat/test-task.R`.

The package is vitals, an R port of the Inspect framework for LLM evaluation.

The source of the original Inspect framework is in inst/inspect_ai. To learn more about anything specific in that package, use the inspect researcher sub-agent.

## Pydantic models and the log viewer

vitals implements .json logging that's compatible with Inspect's Log Viewer. The .json must follow pydantic models defined in Inspect. Much of the code in vitals supports the transformation step from a Task R6 object to a list which can be written to file with `jsonlite::to_json()` or similar. From vitals in R, we can test whether a given log file was written correctly with `devtools::load_all(); expect_valid_log(log_path)`.

When working on logging code:

* Run an Inspect .py file with --log-format=json to generate a log file. You might need to set the envvar `INSPECT_LOG_DIR` to a directory so that you will know where to look for the log file after. 
* Read that log file, 
* Run R code with vitals (there are examples in `inst/` or in documentation) that generates the analogous log. You might set the envvar `VITALS_LOG_DIR` so that you will know where to look for the log file after.  
* Read the resulting file (and probably check it with `expect_valid_log()` if it looks good to you). You will probably want to grep for specific terms that might be related; the logs are quite long, so reading them all at once will use much of your available context.
	* All logs currently pass the Pydantic models. The models may raise validation errors that seem unrelated to a given problem you are working on, but at least one of them is indeed related; the validation errors can be quite noisy.
* Updating the logging code to generate a passing log.

Importantly:

* Once you feel you have a working solution (logs generated from R that pass `expect_valid_log()`, the remaining tests should still pass with `devtools::test()`
* Use your inspect-researcher sub-agent to read more about Inspect AI and how it works.

## Conventions

Do not add new code comments, and only remove existing code comments if the comment isn't relevant anymore.

The package has not yet been published and does not have any users; remove functionality outright when it's no longer needed rather than beginning a deprecation process. No need to worry about breaking changes.

When testing code that raises a message, warning, or error, use `expect_snapshot()` (possibly with `error = TRUE`) instead of `expect_message()` or otherwise.

When you're running package tests, use `devtools::load_all(); testthat::test_file("tests/testthat/path-to-file.R")`. If you encounter namespacing issues, don't delete tests that otherwise should work, and instead ask me what to do.

To get a sense for the style used to write and test code, read `R/task.R` and `tests/testthat/test-task.R`, respectively. Notable, **do not comment your code** besides roxygen comments.

You've been provided with a number of tools that allow you to peruse package documentation; use them liberally. When writing non-base or -tidyverse code, check the help page for functions you use to ensure that you've set function arguments correctly.
