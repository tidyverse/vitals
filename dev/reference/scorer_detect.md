# Scoring with string detection

The following functions use string pattern detection to score model
outputs.

- `detect_includes()`: Determine whether the `target` from the sample
  appears anywhere inside the model output. Can be case sensitive or
  insensitive (defaults to the latter).

- `detect_match()`: Determine whether the `target` from the sample
  appears at the beginning or end of model output (defaults to looking
  at the end). Has options for ignoring case, white-space, and
  punctuation (all are ignored by default).

- `detect_pattern()`: Extract matches of a pattern from the model
  response and determine whether those matches also appear in `target`.

- `detect_answer()`: Scorer for model output that precedes answers with
  "ANSWER: ". Can extract letters, words, or the remainder of the line.

- `detect_exact()`: Scorer which will normalize the text of the answer
  and target(s) and perform an exact matching comparison of the text.
  This scorer will return `CORRECT` when the answer is an exact match to
  one or more targets.

## Usage

``` r
detect_includes(case_sensitive = FALSE)

detect_match(
  location = c("end", "begin", "any", "exact"),
  case_sensitive = FALSE
)

detect_pattern(pattern, case_sensitive = FALSE, all = FALSE)

detect_exact(case_sensitive = FALSE)

detect_answer(format = c("line", "word", "letter"))
```

## Arguments

- case_sensitive:

  Logical, whether comparisons are case sensitive.

- location:

  Where to look for match: one of `"end"`, `"begin"`, `"any"`, or
  `"exact"`. Defaults to `"end"`.

- pattern:

  Regular expression pattern to extract answer.

- all:

  Logical: for multiple captures, whether all must match.

- format:

  What to extract after `"ANSWER:"`: `"letter"`, `"word"`, or `"line"`.
  Defaults to `"line"`.

## Value

A function that scores model output based on string matching. Pass the
returned value to `$eval(scorer)`. See the documentation for the
`scorer` argument in
[Task](https://vitals.tidyverse.org/dev/reference/Task.md) for more
information on the return type.

## See also

[`model_graded_qa()`](https://vitals.tidyverse.org/dev/reference/scorer_model.md)
and
[`model_graded_fact()`](https://vitals.tidyverse.org/dev/reference/scorer_model.md)
for model-based scoring.

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
    solver = generate(solver_chat = chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = detect_includes()
  )

  # evaluate the task (runs solver and scorer)
  tsk$eval()
}
#> ℹ Solving
#> ✔ Solving [1.8s]
#> 
#> ℹ Scoring
#> ✔ Scoring [195ms]
#> 
```
