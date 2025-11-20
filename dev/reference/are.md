# An R Eval

An R Eval is a dataset of challenging R coding problems. Each `input` is
a question about R code which could be solved on first-read only by
experts and, with a chance to read documentation and run some code, by
fluent data scientists. Solutions are in `target()` and enable a fluent
data scientist to evaluate whether the solution deserves full, partial,
or no credit.

Pass this dataset to `Task$new()` to situate it inside of an evaluation
task.

## Usage

``` r
are
```

## Format

A tibble with 29 rows and 7 columns:

- id:

  Character. Unique identifier/title for the code problem.

- input:

  Character. The question to be answered.

- target:

  Character. The solution, often with a description of notable features
  of a correct solution.

- domain:

  Character. The technical domain (e.g., Data Analysis, Programming, or
  Authoring).

- task:

  Character. Type of task (e.g., Debugging, New feature, or
  Translation.)

- source:

  Character. URL or source of the problem. `NA`s indicate that the
  problem was written originally for this eval.

- knowledge:

  List. Required knowledge/concepts for solving the problem.

## Source

Posit Community, GitHub issues, R4DS solutions, etc. For row-level
references, see `source`.

## Examples

``` r
are
#> # A tibble: 29 × 7
#>    id                        input target domain task  source knowledge
#>    <chr>                     <chr> <chr>  <chr>  <chr> <chr>  <list>   
#>  1 after-stat-bar-heights    "Thi… "Pref… Data … New … https… <chr [1]>
#>  2 conditional-grouped-summ… "I h… "One … Data … New … https… <chr [1]>
#>  3 correlated-delays-reason… "Her… "Nota… Data … New … NA     <chr [1]>
#>  4 curl-http-get             "I h… "Ther… Progr… Debu… https… <chr [1]>
#>  5 dropped-level-legend      "I'd… "Also… Data … New … https… <chr [1]>
#>  6 filter-multiple-conditio… "Her… "This… Data … New … NA     <chr [1]>
#>  7 geocode-req-perform       "I a… "You … Data … Debu… https… <chr [1]>
#>  8 group-by-summarize-messa… "Her… "The … Data … New … NA     <chr [1]>
#>  9 grouped-filter-summarize  "Her… "Ther… Data … New … NA     <chr [1]>
#> 10 grouped-geom-line         "Her… "You … Data … New … NA     <chr [1]>
#> # ℹ 19 more rows

dplyr::glimpse(are)
#> Rows: 29
#> Columns: 7
#> $ id        <chr> "after-stat-bar-heights", "conditional-grouped-summ…
#> $ input     <chr> "This bar chart shows the count of different cuts o…
#> $ target    <chr> "Preferably: \n\n```\nggplot(data = diamonds) + \n …
#> $ domain    <chr> "Data analysis", "Data analysis", "Data analysis", …
#> $ task      <chr> "New code", "New code", "New code", "Debugging", "N…
#> $ source    <chr> "https://jrnold.github.io/r4ds-exercise-solutions/d…
#> $ knowledge <list> "tidyverse", "tidyverse", "tidyverse", "r-lib", "t…
```
