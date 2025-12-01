# Model-based scoring

Model-based scoring makes use of a model to score output from a solver.

- `model_graded_qa()` scores how well a solver answers a question/answer
  task.

- `model_graded_fact()` determines whether a solver includes a given
  fact in its response.

The two scorers are quite similar in their implementation, but use a
different default `template` to evaluate correctness.

## Usage

``` r
model_graded_qa(
  template = NULL,
  instructions = NULL,
  grade_pattern = "(?i)GRADE\\s*:\\s*([CPI])(.*)$",
  partial_credit = FALSE,
  scorer_chat = NULL
)

model_graded_fact(
  template = NULL,
  instructions = NULL,
  grade_pattern = "(?i)GRADE\\s*:\\s*([CPI])(.*)$",
  partial_credit = FALSE,
  scorer_chat = NULL
)
```

## Arguments

- template:

  Grading template to use–a `glue()` string which will take
  substitutions `input`, `answer`, `criterion`, `instructions`.

- instructions:

  Grading instructions.

- grade_pattern:

  A regex pattern to extract the final grade from the judge model's
  response.

- partial_credit:

  Whether to allow partial credit.

- scorer_chat:

  An ellmer chat used to grade the model output, e.g.
  [`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html).

## Value

A function that will grade model responses according to the given
instructions. See
[Task](https://vitals.tidyverse.org/dev/reference/Task.md)'s `scorer`
argument for a description of the returned function. The functions that
`model_graded_qa()` and `model_graded_fact()` output can be passed
directly to `$eval()`.

See the documentation for the `scorer` argument in
[Task](https://vitals.tidyverse.org/dev/reference/Task.md) for more
information on the return type.

## See also

[scorer_detect](https://vitals.tidyverse.org/dev/reference/scorer_detect.md)
for string detection-based scoring.

## Examples

``` r
# Quality assurance -----------------------------
if (!identical(Sys.getenv("ANTHROPIC_API_KEY"), "")) {
  # set the log directory to a temporary directory
  withr::local_envvar(VITALS_LOG_DIR = withr::local_tempdir())

  library(ellmer)
  library(tibble)

  simple_addition <- tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(solver_chat = chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = model_graded_qa()
  )

  tsk$eval()
}
#> ℹ Solving
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Solving
#> ✔ Solving [3.6s]
#> 
#> ℹ Scoring
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Scoring
#> ✔ Scoring [5s]
#> 

# Factual response -------------------------------
if (!identical(Sys.getenv("ANTHROPIC_API_KEY"), "")) {
  # set the log directory to a temporary directory
  withr::local_envvar(VITALS_LOG_DIR = withr::local_tempdir())

  library(ellmer)
  library(tibble)

  r_history <- tibble(
    input = c(
      "Who created the R programming language?",
      "In what year was version 1.0 of R released?"
    ),
    target = c("Ross Ihaka and Robert Gentleman.", "2000.")
  )

  tsk <- Task$new(
    dataset = r_history,
    solver = generate(solver_chat = chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = model_graded_fact()
  )

  tsk$eval()
}
#> ℹ Solving
#> ✔ Solving [4.2s]
#> 
#> ℹ Scoring
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Scoring
#> ✔ Scoring [9.1s]
#> 
```
