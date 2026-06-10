# Convert a chat to a solver function

`generate()` is the simplest possible solver one might use with vitals;
it just passes its inputs to the supplied model and returns its raw
responses. The inputs are evaluated in parallel, not in the sense of
multiple R sessions, but in the sense of multiple, asynchronous HTTP
requests using
[`ellmer::parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html).
`generate()`'s output can be passed directory to the `solver` argument
of [Task](https://vitals.tidyverse.org/dev/reference/Task.md)'s `$new()`
method.

## Usage

``` r
generate(solver_chat = NULL)
```

## Arguments

- solver_chat:

  An ellmer chat object, such as from
  [`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
  or a zero-argument function that returns one.

## Value

The output of `generate()` is another function. That function takes in a
vector of `input`s, as well as a solver chat by the name of
`solver_chat` with the default supplied to `generate()` itself.

See the documentation for the `solver` argument in
[Task](https://vitals.tidyverse.org/dev/reference/Task.md) for more
information on the return type.

## See also

[`generate_structured()`](https://vitals.tidyverse.org/dev/reference/generate_structured.md)
for structured output extraction.

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
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Solving
#> ✔ Solving [8.8s]
#> 
#> ℹ Scoring
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Scoring
#> ✔ Scoring [4.8s]
#> 
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ✔ Inspect Viewer running at: <http://127.0.0.1:26308>
#> ✔ Inspect Viewer running at: <http://127.0.0.1:21035>

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
