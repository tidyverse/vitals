# Prepare logs for deployment

This function creates a standalone bundle of the Inspect viewer with log
files that can be deployed statically. It copies the UI viewer files,
log files, and generates the necessary configuration files.

## Usage

``` r
vitals_bundle(log_dir = vitals_log_dir(), output_dir = NULL, overwrite = FALSE)
```

## Arguments

- log_dir:

  Path to the directory containing log files. Defaults to
  [`vitals_log_dir()`](https://vitals.tidyverse.org/dev/reference/vitals_log_dir.md).

- output_dir:

  Path to the directory where the bundled output will be placed.

- overwrite:

  Whether to overwrite an existing output directory. Defaults to FALSE.

## Value

Invisibly returns the output directory path. That directory contains:

    output_dir
    |-- index.html
    |-- robots.txt
    |-- assets
        |--  ..
    |-- logs
        |--  ..

`robots.txt` prevents crawlers from indexing the viewer. That said, many
crawlers only read the `robots.txt` at the root directory of a package,
so the file will likely be ignored if this folder isn't the root
directory of the deployed page. `assets/` is the bundled source for the
viewer. `logs/` is the `log_dir` as well as a `listing.json`, which is a
manifest file for the directory.

## Deployment

This function generates a directory that's ready for deployment to any
static web server such as GitHub Pages, S3 buckets, or Netlify. If you
have a connection to Posit Connect configured, you can deploy a
directory of log files with the following:

    tmp_dir <- withr::local_tempdir()
    vitals_bundle(output_dir = tmp_dir, overwrite = TRUE)
    rsconnect::deployApp(tmp_dir)

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

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = model_graded_qa()
  )

  tsk$eval()

  output_dir <- tempdir()
  vitals_bundle(output_dir = output_dir, overwrite = TRUE)
}
#> ℹ Solving
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Solving
#> ✔ Solving [2.8s]
#> 
#> ℹ Scoring
#> [working] (0 + 0) -> 1 -> 1 | ■■■■■■■■■■■■■■■■                  50%
#> [working] (0 + 0) -> 0 -> 2 | ■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■  100%
#> ℹ Scoring
#> ✔ Scoring [3.6s]
#> 
#> ✔ Bundle /tmp/Rtmp3t7vgO created!
```
