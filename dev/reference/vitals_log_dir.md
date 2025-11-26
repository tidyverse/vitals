# The log directory

vitals supports the `VITALS_LOG_DIR` environment variable, which sets a
default directory to write logs to in
[Task](https://vitals.tidyverse.org/dev/reference/Task.md)'s `$eval()`
and `$log()` methods.

## Usage

``` r
vitals_log_dir()

vitals_log_dir_set(dir)
```

## Arguments

- dir:

  A directory to configure the environment variable `VITALS_LOG_DIR` to.

## Value

Both `vitals_log_dir()` and `vitals_log_dir_set()` return the current
value of the environment variable `VITALS_LOG_DIR`.
`vitals_log_dir_set()` additionally sets it to a new value.

To set this variable in every new R session, you might consider adding
it to your `.Rprofile`, perhaps with `usethis::edit_r_profile()`.

## Examples

``` r
vitals_log_dir()
#> [1] "$RUNNER_TEMP"

dir <- tempdir()

vitals_log_dir_set(dir)

vitals_log_dir()
#> [1] "/tmp/RtmpsG1hQQ"
```
