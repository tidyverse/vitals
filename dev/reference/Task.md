# Creating and evaluating tasks

Evaluation `Task`s provide a flexible data structure for evaluating
LLM-based tools.

1.  **Datasets** contain a set of labelled samples. Datasets are just a
    tibble with columns `input` and `target`, where `input` is a prompt
    and `target` is either literal value(s) or grading guidance.

2.  **Solvers** evaluate the `input` in the dataset and produce a final
    result.

3.  **Scorers** evaluate the final output of solvers. They may use text
    comparisons (like
    [`detect_match()`](https://vitals.tidyverse.org/dev/reference/scorer_detect.md)),
    model grading (like
    [`model_graded_qa()`](https://vitals.tidyverse.org/dev/reference/scorer_model.md)),
    or other custom schemes.

**The usual flow of LLM evaluation with Tasks calls `$new()` and then
`$eval()`.** `$eval()` just calls `$solve()`, `$score()`, `$measure()`,
`$log()`, and `$view()` in order. The remaining methods are generally
only recommended for expert use.

## See also

[`generate()`](https://vitals.tidyverse.org/dev/reference/generate.md)
for the simplest possible solver, and
[scorer_model](https://vitals.tidyverse.org/dev/reference/scorer_model.md)
and
[scorer_detect](https://vitals.tidyverse.org/dev/reference/scorer_detect.md)
for two built-in approaches to scoring.

## Public fields

- `dir`:

  The directory where evaluation logs will be written to. Defaults to
  [`vitals_log_dir()`](https://vitals.tidyverse.org/dev/reference/vitals_log_dir.md).

- `metrics`:

  A named vector of metric values resulting from `$measure()` (called
  inside of `$eval()`). Will be `NULL` if metrics have yet to be
  applied.

## Methods

### Public methods

- [`Task$new()`](#method-Task-initialize)

- [`Task$eval()`](#method-Task-eval)

- [`Task$get_samples()`](#method-Task-get_samples)

- [`Task$solve()`](#method-Task-solve)

- [`Task$score()`](#method-Task-score)

- [`Task$measure()`](#method-Task-measure)

- [`Task$log()`](#method-Task-log)

- [`Task$view()`](#method-Task-view)

- [`Task$set_solver()`](#method-Task-set_solver)

- [`Task$set_scorer()`](#method-Task-set_scorer)

- [`Task$set_metrics()`](#method-Task-set_metrics)

- [`Task$get_cost()`](#method-Task-get_cost)

- [`Task$clone()`](#method-Task-clone)

------------------------------------------------------------------------

### `Task$new()`

The typical flow of LLM evaluation with vitals tends to involve first
calling this method and then `$eval()` on the resulting object.

#### Usage

    Task$new(
      dataset,
      solver,
      scorer,
      metrics = NULL,
      epochs = NULL,
      name = NULL,
      dir = vitals_log_dir()
    )

#### Arguments

- `dataset`:

  A tibble with, minimally, columns `input` and `target`. The `input`
  column can be either a character vector or a list-column of 1-row
  tibbles. Using 1-row tibbles allows per-sample customization by
  including additional metadata that custom solvers can access.

- `solver`:

  A function that takes a vector of inputs from the dataset's `input`
  column as its first argument and determines values approximating
  `dataset$target`. Its return value must be a list with the following
  elements:

  - `result` - A character vector of the final responses, with the same
    length as `dataset$input`.

  - `solver_chat` - A list of ellmer Chat objects that were used to
    solve each input, also with the same length as `dataset$input`.

  Additional output elements can be included in a slot `solver_metadata`
  that has the same length as `dataset$input`, which will be logged in
  `solver_metadata`.

  Additional arguments can be passed to the solver via `$solve(...)` or
  `$eval(...)`. See the definition of
  [`generate()`](https://vitals.tidyverse.org/dev/reference/generate.md)
  for a function that outputs a valid solver that just passes inputs to
  ellmer Chat objects' `$chat()` method in parallel.

- `scorer`:

  A function that evaluates how well the solver's return value
  approximates the corresponding elements of `dataset$target`. The
  function should take in the `$get_samples()` slot of a Task object and
  return a list with the following elements:

  - `score` - A vector of scores with length equal to `nrow(samples)`.
    Built-in scorers return ordered factors with levels `I` \< `P`
    (optionally) \< `C` (standing for "Incorrect", "Partially Correct",
    and "Correct"). If your scorer returns this output type, the package
    will automatically calculate metrics.

  Optionally:

  - `scorer_chat` - If your scorer makes use of ellmer, also include a
    list of ellmer Chat objects that were used to score each result,
    also with length `nrow(samples)`.

  - `scorer_metadata` - Any intermediate results or other values that
    you'd like to be stored in the persistent log. This should also have
    length equal to `nrow(samples)`.

  Scorers will probably make use of `samples$input`, `samples$target`,
  and `samples$result` specifically. See [model-based
  scoring](https://vitals.tidyverse.org/dev/reference/scorer_model.md)
  for examples.

- `metrics`:

  A named list of functions that take in a vector of scores (as in
  `task$get_samples()$score`) and output a single numeric value.

- `epochs`:

  The number of times to repeat each sample. Evaluate each sample
  multiple times to better quantify variation. Optional, defaults to
  `1L`. The value of `epochs` supplied to `$eval()` or `$score()` will
  take precedence over the value in `$new()`.

- `name`:

  A name for the evaluation task. Defaults to
  `deparse(substitute(dataset))`.

- `dir`:

  Directory where logs should be stored.

#### Returns

A new Task object.

------------------------------------------------------------------------

### `Task$eval()`

Evaluates the task by running the solver, scorer, logging results, and
viewing (if interactive). This method works by calling `$solve()`,
`$score()`, `$log()`, and `$view()` in sequence.

The typical flow of LLM evaluation with vitals tends to involve first
calling `$new()` and then this method on the resulting object.

#### Usage

    Task$eval(..., epochs = NULL, view = interactive())

#### Arguments

- `...`:

  Additional arguments passed to the solver and scorer functions. All
  arguments must be named. Arguments are routed based on function
  signatures: if an argument name matches a parameter in the solver, it
  goes to the solver; if it matches a parameter in the scorer, it goes
  to the scorer. Arguments matching both go to both. Unmatched arguments
  are passed to any function with `...` in its signature. An error is
  raised if an argument matches neither function and neither accepts
  `...`.

- `epochs`:

  The number of times to repeat each sample. Evaluate each sample
  multiple times to better quantify variation. Optional, defaults to
  `1L`. The value of `epochs` supplied to `$eval()` or `$score()` will
  take precedence over the value in `$new()`.

- `view`:

  Automatically open the viewer after evaluation (defaults to TRUE if
  interactive, FALSE otherwise).

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$get_samples()`

The task's samples represent the evaluation in a data frame format.

[`vitals_bind()`](https://vitals.tidyverse.org/dev/reference/vitals_bind.md)
row-binds the output of this function called across several tasks.

#### Usage

    Task$get_samples()

#### Returns

A tibble representing the evaluation. Based on the `dataset`, `epochs`
may duplicate rows, and the solver and scorer will append columns to
this data.

------------------------------------------------------------------------

### `Task$solve()`

Solve the task by running the solver

#### Usage

    Task$solve(..., epochs = NULL)

#### Arguments

- `...`:

  Additional arguments passed to the solver function.

- `epochs`:

  The number of times to repeat each sample. Evaluate each sample
  multiple times to better quantify variation. Optional, defaults to
  `1L`. The value of `epochs` supplied to `$eval()` or `$score()` will
  take precedence over the value in `$new()`.

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$score()`

Score the task by running the scorer and then applying metrics to its
results.

#### Usage

    Task$score(...)

#### Arguments

- `...`:

  Additional arguments passed to the scorer function.

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$measure()`

Applies metrics to a scored Task.

#### Usage

    Task$measure()

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$log()`

Log the task to a directory.

Note that, if an `VITALS_LOG_DIR` envvar is set, this will happen
automatically in `$eval()`.

#### Usage

    Task$log(dir = self$dir)

#### Arguments

- `dir`:

  The directory to write the log to.

#### Returns

The path to the logged file, invisibly.

------------------------------------------------------------------------

### `Task$view()`

View the task results in the Inspect log viewer

#### Usage

    Task$view()

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$set_solver()`

Set the solver function

#### Usage

    Task$set_solver(solver)

#### Arguments

- `solver`:

  A function that takes a vector of inputs from the dataset's `input`
  column as its first argument and determines values approximating
  `dataset$target`. Its return value must be a list with the following
  elements:

  - `result` - A character vector of the final responses, with the same
    length as `dataset$input`.

  - `solver_chat` - A list of ellmer Chat objects that were used to
    solve each input, also with the same length as `dataset$input`.

  Additional output elements can be included in a slot `solver_metadata`
  that has the same length as `dataset$input`, which will be logged in
  `solver_metadata`.

  Additional arguments can be passed to the solver via `$solve(...)` or
  `$eval(...)`. See the definition of
  [`generate()`](https://vitals.tidyverse.org/dev/reference/generate.md)
  for a function that outputs a valid solver that just passes inputs to
  ellmer Chat objects' `$chat()` method in parallel.

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$set_scorer()`

Set the scorer function

#### Usage

    Task$set_scorer(scorer)

#### Arguments

- `scorer`:

  A function that evaluates how well the solver's return value
  approximates the corresponding elements of `dataset$target`. The
  function should take in the `$get_samples()` slot of a Task object and
  return a list with the following elements:

  - `score` - A vector of scores with length equal to `nrow(samples)`.
    Built-in scorers return ordered factors with levels `I` \< `P`
    (optionally) \< `C` (standing for "Incorrect", "Partially Correct",
    and "Correct"). If your scorer returns this output type, the package
    will automatically calculate metrics.

  Optionally:

  - `scorer_chat` - If your scorer makes use of ellmer, also include a
    list of ellmer Chat objects that were used to score each result,
    also with length `nrow(samples)`.

  - `scorer_metadata` - Any intermediate results or other values that
    you'd like to be stored in the persistent log. This should also have
    length equal to `nrow(samples)`.

  Scorers will probably make use of `samples$input`, `samples$target`,
  and `samples$result` specifically. See [model-based
  scoring](https://vitals.tidyverse.org/dev/reference/scorer_model.md)
  for examples.

#### Returns

The Task object (invisibly)

------------------------------------------------------------------------

### `Task$set_metrics()`

Set the metrics that will be applied in `$measure()` (and thus
`$eval()`).

#### Usage

    Task$set_metrics(metrics)

#### Arguments

- `metrics`:

  A named list of functions that take in a vector of scores (as in
  `task$get_samples()$score`) and output a single numeric value.

#### Returns

The Task (invisibly)

------------------------------------------------------------------------

### `Task$get_cost()`

The cost of this eval This is a wrapper around ellmer's `$token_usage()`
function. That function is called at the beginning and end of each call
to `$solve()` and `$score()`; this function returns the cost inferred by
taking the differences in values of `$token_usage()` over time.

#### Usage

    Task$get_cost()

#### Returns

A tibble displaying the cost of solving and scoring the evaluation by
model, separately for the solver and scorer.

------------------------------------------------------------------------

### `Task$clone()`

The objects of this class are cloneable with this method.

#### Usage

    Task$clone(deep = FALSE)

#### Arguments

- `deep`:

  Whether to make a deep clone.

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
#> ✔ Solving [1.9s]
#> 
#> ℹ Scoring
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Scoring
#> ✔ Scoring [3.1s]
#> 
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ✔ Inspect Viewer running at: <http://127.0.0.1:9826>
#> ✔ Inspect Viewer running at: <http://127.0.0.1:15823>

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
