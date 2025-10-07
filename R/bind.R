#' Concatenate task samples for analysis
#'
#' @description
#' Combine multiple [Task] objects into a single tibble for comparison.
#'
#' This function takes multiple (optionally named) [Task] objects and row-binds
#' their `$get_samples()` together, adding a `task` column to identify the source of each
#' row. The resulting tibble nests additional columns into a `metadata` column
#' and is ready for further analysis.
#'
#' @param ... `Task` objects to combine, optionally named.
#'
#' @returns A tibble with the combined samples from all tasks, with a `task`
#' column indicating the source and a nested `metadata` column containing
#' additional fields.
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
#'   tsk1 <- Task$new(
#'     dataset = simple_addition,
#'     solver = generate(chat_anthropic(model = "claude-sonnet-4-5-20250929")),
#'     scorer = model_graded_qa()
#'   )
#'   tsk1$eval()
#'
#'   tsk2 <- Task$new(
#'     dataset = simple_addition,
#'     solver = generate(chat_anthropic(model = "claude-sonnet-4-5-20250929")),
#'     scorer = detect_includes()
#'   )
#'   tsk2$eval()
#'
#'   combined <- vitals_bind(model_graded = tsk1, string_detection = tsk2)
#' }
#'
#' @export
vitals_bind <- function(...) {
  x <- dots_list(..., .named = TRUE)
  lapply(x, check_inherits, cls = "Task", call = caller_env(0))

  x <- purrr::map2(x, names(x), function(task, task_name) {
    dplyr::mutate(
      task$get_samples(),
      task = task_name,
      .before = everything()
    )
  })

  res <- purrr::list_rbind(x)
  res <- tidyr::nest(
    res,
    .by = any_of(c("task", "id", "epoch", "score")),
    .key = "metadata"
  )
  res
}
