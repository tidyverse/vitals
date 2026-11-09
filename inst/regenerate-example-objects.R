# Runs the code to regenerate example eval objects used in the package.
regenerate_example_objects <- function() {
  devtools::load_all()

  cli::cli_progress_step("Regenerating `are` on 1 epoch")
  regenerate_are_1e()

  cli::cli_progress_step("Regenerating `are` with custom solvers")
  regenerate_are_custom_solvers()

  cli::cli_progress_step(
    "Regenerating `are` with 3 epochs for analysis article"
  )
  regenerate_are_3e_analysis()

  cli::cli_progress_done()
}

# An R Eval on 1 epoch, via the intro vignette ------------------------
regenerate_are_1e <- function() {
  json_files <- list.files(
    "vignettes/articles/data/vitals/logs",
    pattern = "\\.json$",
    full.names = TRUE
  )
  if (length(json_files) > 0) {
    file.remove(json_files)
  }

  withr::local_envvar(VITALS_SHOULD_EVAL = "true")
  rmarkdown::render('vignettes/vitals.Rmd')
}

# An R Eval on 1 epoch, via the intro vignette ------------------------
regenerate_are_custom_solvers <- function() {
  json_files <- list.files(
    "vignettes/articles/data/solvers/logs",
    pattern = "\\.json$",
    full.names = TRUE
  )
  if (length(json_files) > 0) {
    file.remove(json_files)
  }

  withr::local_envvar(VITALS_SHOULD_EVAL = "true")
  rmarkdown::render('vignettes/articles/solvers.Rmd')
}

# An R Eval on 3 epoch x 3 models, via the analysis article -----------------
regenerate_are_3e_analysis <- function() {
  json_files <- list.files(
    "vignettes/articles/data/analysis/logs",
    pattern = "\\.json$",
    full.names = TRUE
  )
  if (length(json_files) > 0) {
    file.remove(json_files)
  }

  withr::local_envvar(VITALS_SHOULD_EVAL = "true")
  rmarkdown::render("vignettes/articles/analysis.Rmd")
}

regenerate_example_objects()
