# Concatenate task samples for analysis

Combine multiple
[Task](https://vitals.tidyverse.org/dev/reference/Task.md) objects into
a single tibble for comparison.

This function takes multiple (optionally named)
[Task](https://vitals.tidyverse.org/dev/reference/Task.md) objects and
row-binds their `$get_samples()` together, adding a `task` column to
identify the source of each row. The resulting tibble nests additional
columns into a `metadata` column and is ready for further analysis.

## Usage

``` r
vitals_bind(...)
```

## Arguments

- ...:

  `Task` objects to combine, optionally named.

## Value

A tibble with the combined samples from all tasks, with a `task` column
indicating the source and a nested `metadata` column containing
additional fields.

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

  tsk1 <- Task$new(
    dataset = simple_addition,
    solver = generate(chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = model_graded_qa()
  )
  tsk1$eval()

  tsk2 <- Task$new(
    dataset = simple_addition,
    solver = generate(chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = detect_includes()
  )
  tsk2$eval()

  combined <- vitals_bind(model_graded = tsk1, string_detection = tsk2)
}
#> ℹ Solving
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Solving
#> ✔ Solving [1.4s]
#> 
#> ℹ Scoring
#> ✔ Scoring [2.4s]
#> 
#> ℹ Solving
#> ✔ Solving [1.3s]
#> 
#> ℹ Scoring
#> ✔ Scoring [41ms]
#> 
```
