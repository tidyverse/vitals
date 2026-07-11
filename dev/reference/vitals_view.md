# Interactively view local evaluation logs

vitals bundles the Inspect log viewer, an interactive app for exploring
evaluation logs. Supply a path to a directory of tasks written to json.
For individual
[Task](https://vitals.tidyverse.org/dev/reference/Task.md) objects, use
the `$view()` method instead.

## Usage

``` r
vitals_view(dir = vitals_log_dir(), host = "127.0.0.1", port = NULL)
```

## Arguments

- dir:

  Path to a directory containing task eval logs.

- host:

  Host to serve on. Defaults to "127.0.0.1".

- port:

  Port to serve on. If NULL, will find a random available port.

## Value

The server object (invisibly)

## Examples

``` r
if (!identical(Sys.getenv("ANTHROPIC_API_KEY"), "")) {
  # set the log directory to a temporary directory
  withr::local_envvar(VITALS_LOG_DIR = withr::local_tempdir())

  library(ellmer)
  library(tibble)

  simple_addition <- tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  # create a new Task
  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = model_graded_qa()
  )

  # evaluate the task (runs solver and scorer) and opens
  # the results in the Inspect log viewer (if interactive)
  tsk$eval()

  # $eval() is shorthand for:
  tsk$solve()
  tsk$score()
  tsk$measure()
  tsk$log()
  tsk$view()

  # get the evaluation results as a data frame
  tsk$get_samples()

  # view the task directory with $view() or vitals_view()
  vitals_view()
}
#> ℹ Solving
#> ✔ Solving [1.5s]
#> 
#> ℹ Scoring
#> ✔ Scoring [2.9s]
#> 
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ✔ Inspect Viewer running at: <http://127.0.0.1:18428>
#> ✔ Inspect Viewer running at: <http://127.0.0.1:23974>

# The `input` column can be a list of 1-row tibbles for per-sample metadata.
# Custom solvers can then extract columns from each input:
shapes_data <- tibble::tibble(
  input = list(
    tibble::tibble(shapes = "square, circle, rhombus", pick = "square"),
    tibble::tibble(shapes = "square, circle, rhombus", pick = "circle")
  ),
  target = c("square", "circle")
)

my_solver <- function(solver_chat = NULL) {
  chat <- solver_chat
  function(inputs, ..., solver_chat = chat) {
    ch <- if (is.function(solver_chat)) solver_chat() else solver_chat$clone()
    prompts <- lapply(inputs, function(inp) {
      paste0("Always pick ", inp$pick, ". Return only that shape.\n\n", inp$shapes)
    })
    res <- ellmer::parallel_chat(ch, prompts, ...)
    list(result = purrr::map_chr(res, \(c) c$last_turn()@text), solver_chat = res)
  }
}
```
