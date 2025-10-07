#' Creating and evaluating tasks
#'
#' @description
#' Evaluation `Task`s provide a flexible data structure for evaluating LLM-based
#' tools.
#'
#' 1) **Datasets** contain a set of labelled samples. Datasets are just a
#' tibble with columns `input` and `target`, where `input` is a prompt
#' and `target` is either literal value(s) or grading guidance.
#' 2) **Solvers** evaluate the `input` in the dataset and produce a final result.
#' 3) **Scorers** evaluate the final output of solvers. They may use text
#' comparisons (like [detect_match()]), model grading (like
#' [model_graded_qa()]), or other custom schemes.
#'
#' **The usual flow of LLM evaluation with Tasks calls `$new()` and then `$eval()`.**
#' `$eval()` just calls `$solve()`, `$score()`, `$measure()`, `$log()`,
#' and `$view()` in order. The remaining methods are generally only
#' recommended for expert use.
#'
#' @param solver A function that takes a vector of inputs from the
#' dataset's `input` column as its first argument and determines values
#' approximating `dataset$target`. Its return value must be a list with
#' the following elements:
#'
#' * `result` - A character vector of the final responses, with the same length
#'   as `dataset$input`.
#' * `solver_chat` - A list of ellmer Chat objects that were used to solve
#'   each input, also with the same length as `dataset$input`.
#'
#' Additional output elements can be included in a slot `solver_metadata` that
#' has the same length as `dataset$input`, which will be logged in
#' `solver_metadata`.
#'
#' Additional arguments can be passed to the solver via `$solve(...)`
#' or `$eval(...)`. See the definition of [generate()] for a function that
#' outputs a valid solver that just passes inputs to ellmer Chat objects'
#' `$chat()` method in parallel.
#'
#' @param scorer A function that evaluates how well the solver's return value
#' approximates the corresponding elements of `dataset$target`. The function
#' should take in the `$get_samples()` slot of a Task object and return a list with
#' the following elements:
#'
#' * `score` - A vector of scores with length equal to `nrow(samples)`.
#'   Built-in scorers return ordered factors with
#'   levels `I` < `P` (optionally) < `C` (standing for "Incorrect", "Partially
#'   Correct", and "Correct"). If your scorer returns this output type, the
#'   package will automatically calculate metrics.
#'
#' Optionally:
#' * `scorer_chat` - If your scorer makes use of ellmer, also include a list of
#'   ellmer Chat objects that were used to score each result, also with
#'   length `nrow(samples)`.
#' * `scorer_metadata` - Any intermediate results or other values that you'd
#'   like to be stored in the persistent log. This should also have length
#'   equal to `nrow(samples)`.
#'
#' Scorers will probably make use of `samples$input`, `samples$target`, and
#' `samples$result` specifically. See [model-based scoring][scorer_model]
#' for examples.
#'
#' @param metrics A named list of functions that take in a vector of scores
#' (as in `task$get_samples()$score`) and output a single numeric value.
#'
#' @param epochs The number of times to repeat each sample. Evaluate each sample
#' multiple times to better quantify variation. Optional, defaults to `1L`.
#' The value of `epochs` supplied to `$eval()` or `$score()` will take
#' precedence over the value in `$new()`.
#'
#' @seealso [generate()] for the simplest possible solver, and
#' [scorer_model] and [scorer_detect] for two built-in approaches to
#' scoring.
#' @examples
#' if (!identical(Sys.getenv("ANTHROPIC_API_KEY"), "")) {
#'   # set the log directory to a temporary directory
#'   withr::local_envvar(VITALS_LOG_DIR = withr::local_tempdir())
#'
#'   library(ellmer)
#'   library(tibble)
#'
#'   simple_addition <- tibble(
#'     input = c("What's 2+2?", "What's 2+3?"),
#'     target = c("4", "5")
#'   )
#'
#'   # create a new Task
#'   tsk <- Task$new(
#'     dataset = simple_addition,
#'     solver = generate(chat_anthropic(model = "claude-sonnet-4-5-20250929")),
#'     scorer = model_graded_qa()
#'   )
#'
#'   # evaluate the task (runs solver and scorer) and opens
#'   # the results in the Inspect log viewer (if interactive)
#'   tsk$eval()
#'
#'   # $eval() is shorthand for:
#'   tsk$solve()
#'   tsk$score()
#'   tsk$measure()
#'   tsk$log()
#'   tsk$view()
#'
#'   # get the evaluation results as a data frame
#'   tsk$get_samples()
#'
#'   # view the task directory with $view() or vitals_view()
#'   vitals_view()
#' }
#'
#' @export
Task <- R6::R6Class(
  "Task",
  lock_objects = FALSE,
  public = list(
    #' @field dir The directory where evaluation logs will be written to. Defaults
    #' to `vitals_log_dir()`.
    dir = vitals_log_dir(),

    #' @field metrics A named vector of metric values resulting from `$measure()`
    #' (called inside of `$eval()`). Will be `NULL` if metrics have yet to
    #' be applied.
    metrics = NULL,

    #' @description
    #' The typical flow of LLM evaluation with vitals tends to involve first
    #' calling this method and then `$eval()` on the resulting object.
    #'
    #' @param dataset A tibble with, minimally, columns `input` and `target`.
    #' @param name A name for the evaluation task. Defaults to
    #' `deparse(substitute(dataset))`.
    #' @param dir Directory where logs should be stored.
    #'
    #' @return A new Task object.
    initialize = function(
      dataset,
      solver,
      scorer,
      metrics = NULL,
      epochs = NULL,
      name = deparse(substitute(dataset)),
      dir = vitals_log_dir()
    ) {
      force(name)

      solver_name <- deparse(substitute(solver))
      scorer_name <- deparse(substitute(scorer))
      metrics_name <- deparse(substitute(metrics))

      check_dataset(dataset)
      check_log_dir(dir)
      check_function(solver)
      # TODO: for non-built in scorers, what to do?
      check_metrics(metrics)
      check_number_whole(epochs, min = 1, allow_null = TRUE)

      # dataset names can contain dashes or alphanumerics--transition
      # underscores and spaces to dashes (#92)
      private$dataset_name <- gsub(
        "[^[:alnum:]\\-]",
        "",
        gsub("_| ", "-", name)
      )
      self$dir <- dir
      private$solver <- logged(solver, fn_name = solver_name)
      private$scorer <- logged(scorer, fn_name = scorer_name)

      if (!is.null(metrics)) {
        private$metric_fns <- metrics
      }

      private$task_id <- substr(hash(c(name, solver_name, scorer_name)), 1, 22)
      private$epochs <- epochs

      private$samples <- set_id_column(dataset)
    },

    #' @description
    #' Evaluates the task by running the solver, scorer, logging results, and
    #' viewing (if interactive). This method works by calling `$solve()`,
    #' `$score()`, `$log()`, and `$view()` in sequence.
    #'
    #' The typical flow of LLM evaluation with vitals tends to involve first
    #' calling `$new()` and then this method on the resulting object.
    #'
    #' @param ... Additional arguments passed to the solver and scorer functions.
    #' All arguments must be named. Arguments are routed based on function
    #' signatures: if an argument name matches a parameter in the solver, it goes
    #' to the solver; if it matches a parameter in the scorer, it goes to the
    #' scorer. Arguments matching both go to both. Unmatched arguments are passed
    #' to any function with `...` in its signature. An error is raised if an
    #' argument matches neither function and neither accepts `...`.
    #' @param view Automatically open the viewer after evaluation (defaults to
    #' TRUE if interactive, FALSE otherwise).
    #'
    #' @return The Task object (invisibly)
    eval = function(..., epochs = NULL, view = interactive()) {
      check_number_whole(epochs, min = 1, allow_null = TRUE)

      if (private$solved || private$scored) {
        private$reset_for_new_eval()
      }

      dots <- list(...)
      if (
        length(dots) > 0 && (is.null(names(dots)) || any(names(dots) == ""))
      ) {
        cli::cli_abort(
          "All arguments in {.code ...} must be named.",
          call = call2("$eval()")
        )
      }

      split_args <- private$split_dots(dots)

      cli::cli_progress_step("Solving")
      do.call(self$solve, c(split_args$solver, list(epochs = epochs)))

      cli::cli_progress_step("Scoring")
      do.call(self$score, split_args$scorer)
      self$measure()

      self$log(self$dir)
      private$stash_last_task()

      cli::cli_progress_done()
      if (view) {
        self$view()
      }

      invisible(self)
    },

    #' @description
    #' The task's samples represent the evaluation in a data frame format.
    #'
    #' [vitals_bind()] row-binds the output of this
    #' function called across several tasks.
    #'
    #' @return
    #' A tibble representing the evaluation. Based on the `dataset`,
    #' `epochs` may duplicate rows, and the solver and scorer will append
    #' columns to this data.
    get_samples = function() {
      private$samples
    },

    #' @description
    #' Solve the task by running the solver
    #'
    #' @param ... Additional arguments passed to the solver function.
    #'
    #' @return The Task object (invisibly)
    solve = function(..., epochs = NULL) {
      withr::local_envvar(IN_VITALS_EVAL = "true")
      check_number_whole(epochs, min = 1, allow_null = TRUE)

      if (private$solved) {
        private$reset_for_new_eval()
      }

      private$timestamps$solve$started_at <- Sys.time()

      private$samples <- join_epochs(
        self$get_samples(),
        epochs %||% private$epochs
      )

      private$run_id <- generate_id()

      private$samples$result <- NA
      private$samples$solver_chat <- NA

      private$track_token_usage("solver_token_usage")
      private$solutions <- private$solver(self$get_samples()$input, ...)

      # TODO: it might be nice to just run one of the inputs async and check for
      # this earlier on so that a full eval's worth of results isn't thrown
      # away if the output format isn't quite right.
      private$check_solver_outputs()
      private$cbind_solutions()

      private$solved <- TRUE
      private$timestamps$solve$completed_at <- Sys.time()
      invisible(self)
    },

    #' @description
    #' Score the task by running the scorer and then applying metrics to
    #' its results.
    #'
    #' @param ... Additional arguments passed to the scorer function.
    #'
    #' @return The Task object (invisibly)
    score = function(...) {
      withr::local_envvar(IN_VITALS_EVAL = "true")
      if (!private$solved) {
        cli::cli_alert_warning(
          "Task has not been solved yet. Run task$solve() first."
        )
        return(invisible(self))
      }

      private$timestamps$score$started_at <- Sys.time()
      private$samples$score <- NA

      private$track_token_usage("scorer_token_usage")
      private$scores <- private$scorer(self$get_samples(), ...)
      private$check_scorer_outputs()
      private$cbind_scores()

      private$scored <- TRUE
      private$timestamps$score$completed_at <- Sys.time()
      invisible(self)
    },

    #' @description
    #' Applies metrics to a scored Task.
    #'
    #' @return The Task object (invisibly)
    measure = function() {
      if (!private$scored) {
        cli::cli_abort(
          "Task has not been scored yet. Run task$score() first."
        )
      }

      if (!is.null(private$metric_fns)) {
        private$apply_metrics()
      } else {
        private$apply_naive_accuracy()
      }

      private$check_metric_output()
      self$metrics <- purrr::map_dbl(
        private$metric_results,
        purrr::pluck,
        "value"
      )

      invisible(self)
    },

    #' @description
    #' Log the task to a directory.
    #'
    #' Note that, if an `VITALS_LOG_DIR` envvar is set, this will happen
    #' automatically in `$eval()`.
    #'
    #' @param dir The directory to write the log to.
    #'
    #' @return The path to the logged file, invisibly.
    log = function(dir = self$dir) {
      if (!private$scored) {
        cli::cli_abort(
          "Task has not been scored yet. Run task$score() first."
        )
      }

      samples <- self$get_samples()
      samples <- private$add_working_times(samples)
      samples <- private$add_working_starts(samples)

      scorer_name <- private$scores$name
      if ("scorer_chat" %in% names(samples)) {
        scorer_name <- paste0(
          c(
            scorer_name,
            " (",
            samples$scorer_chat[[1]]$get_model(),
            ")"
          ),
          collapse = ""
        )
      }

      eval_log <- eval_log(
        eval = translate_to_eval(
          run_id = private$run_id,
          task = private$dataset_name,
          task_id = private$task_id,
          dataset = list(
            samples = length(unique(samples$id)),
            sample_ids = as.list(seq_len(length(unique(samples$id)))),
            shuffled = FALSE
          ),
          model = private$solver_description(),
          scorers = translate_to_eval_scorers(
            name = samples$scorer[[1]]
          )
        ),
        plan = translate_to_plan(
          steps = translate_to_plan_steps(
            name = private$solver_description(),
            arguments = private$solutions$arguments,
            system_prompt = private$samples$solver_chat[[1]]$get_system_prompt()
          )
        ),
        results = translate_to_results(
          total_samples = nrow(samples),
          completed_samples = nrow(samples),
          scores = results_scores(
            name = scorer_name,
            metrics = map(private$metric_results, rename_metric_fields)
          )
        ),
        stats = translate_to_stats(
          started_at = eval_log_timestamp(private$timestamps$solve$started_at),
          completed_at = eval_log_timestamp(
            private$timestamps$score$completed_at
          ),
          model_usage = sum_model_usage(samples$solver_chat)
        ),
        samples = translate_to_samples(
          samples,
          scores = private$scores,
          timestamps = private$timestamps
        )
      )

      if (is.na(dir)) {
        self$dir <- tempdir()
      }

      log_path <- eval_log_write(eval_log, dir = self$dir)

      invisible(log_path)
    },

    #' @description
    #' View the task results in the Inspect log viewer
    #'
    #' @return The Task object (invisibly)
    view = function() {
      if (!private$solved) {
        cli::cli_alert_warning(
          "Task has not been evaluated yet. Run task$eval() first."
        )
        return(invisible(self))
      }

      vitals_view(self$dir)
      invisible(self)
    },

    #' @description
    #' Set the solver function
    #'
    #' @return The Task object (invisibly)
    set_solver = function(solver) {
      solver_name <- deparse(substitute(solver))
      private$solver <- logged(solver, fn_name = solver_name)

      private$reset_solutions()

      invisible(self)
    },

    #' @description
    #' Set the scorer function
    #'
    #' @return The Task object (invisibly)
    set_scorer = function(scorer) {
      scorer_name <- deparse(substitute(scorer))
      private$scorer <- logged(scorer, fn_name = scorer_name)
      private$reset_scores()

      invisible(self)
    },

    #' @description
    #' Set the metrics that will be applied in `$measure()` (and thus `$eval()`).
    #'
    #' @return The Task (invisibly)
    set_metrics = function(metrics) {
      metrics_name <- deparse(substitute(metrics))

      if (is.null(metrics)) {
        private$metric_fns <- NULL
      }

      check_metrics(metrics)
      private$metric_fns <- metrics
      private$reset_metrics()

      invisible(self)
    },

    #' @description The cost of this eval
    #' This is a wrapper around ellmer's `$token_usage()` function.
    #' That function is called at the beginning and end of each call to
    #' `$solve()` and `$score()`; this function returns the cost inferred
    #' by taking the differences in values of `$token_usage()` over time.
    #'
    #' @return A tibble displaying the cost of solving and scoring the
    #' evaluation by model, separately for the solver and scorer.
    get_cost = function() {
      bind_token_usage(
        private$solver_token_usage,
        private$scorer_token_usage
      )
    }
  ),

  private = list(
    dataset_name = NULL,

    solver = NULL,
    solver_token_usage = NULL,
    solved = FALSE,

    solver_description = function() {
      sub_name <- private$solutions$name
      model_name <- private$samples$solver_chat[[1]]$get_model()

      sub_name <- gsub("model = ", "", sub_name, fixed = TRUE)
      sub_name <- gsub(model_name, "", sub_name, fixed = TRUE)
      sub_name <- gsub("\"\"", "", sub_name)
      paste0(
        c(
          sub_name,
          " (",
          model_name,
          ")"
        ),
        collapse = ""
      )
    },

    scorer = NULL,
    scorer_token_usage = NULL,
    scored = FALSE,

    samples = NULL,

    # log when solving/scoring starts
    # eventually, this will be derived from the chats themselves (#112)
    timestamps = list(),

    stash_last_task = function() {
      if (!"pkg:vitals" %in% search()) {
        do.call(
          "attach",
          list(new.env(), pos = length(search()), name = "pkg:vitals")
        )
      }
      env <- as.environment("pkg:vitals")
      env$.last_task <- self
      invisible(NULL)
    },

    reset_solutions = function() {
      private$samples$result <- NA
      private$samples$solver_chat <- NULL
      private$samples$solver_metadata <- NULL
      private$timestamps$solve <- NULL
      private$solved <- FALSE

      if ("epoch" %in% names(self$get_samples())) {
        private$samples <- private$samples[
          private$samples$epoch == 1,
        ]
        private$samples$epoch <- NULL
      }

      if (private$scored) {
        private$reset_scores()
      }

      invisible(NULL)
    },

    reset_scores = function() {
      private$samples$score <- NA
      private$samples$scorer_chat <- NULL
      private$samples$scorer_metadata <- NULL
      private$timestamps$score <- NULL
      private$scored <- FALSE

      if (!is.null(self$metrics)) {
        private$reset_metrics()
      }

      invisible(NULL)
    },

    reset_metrics = function() {
      self$metrics <- NULL
    },

    reset_for_new_eval = function() {
      private$reset_solutions()
      private$reset_scores()
      invisible(NULL)
    },

    check_solver_outputs = function() {
      if (
        !all(c("result", "solver_chat") %in% names(private$solutions$value))
      ) {
        cli::cli_abort(
          "{.arg solver} must return slots {.field result} and 
           {.field solver_chat}.",
          call = call2("$solve()")
        )
      }

      first_solver_chat <- private$solutions$value$solver_chat[[1]]
      if (!inherits(first_solver_chat, "Chat")) {
        cli::cli_abort(
          "Elements in the {.field solver_chat} output from {.arg solver} must be
           ellmer Chat objects, not {.obj_type_friendly {first_solver_chat}}.",
          call = call2("$solve()")
        )
      }
    },

    check_scorer_outputs = function() {
      if (!"score" %in% names(private$scores$value)) {
        cli::cli_abort(
          "{.arg scorer} must return a list with (at least) the slot {.field score}.",
          call = call2("$score()")
        )
      }

      if (!"scorer_chat" %in% names(private$scores$value)) {
        return(invisible())
      }

      first_scorer_chat <- private$scores$value$scorer_chat[[1]]
      if (!inherits(first_scorer_chat, "Chat")) {
        cli::cli_abort(
          "Elements in the {.field scorer_chat} output from {.arg scorer} must be
           ellmer Chat objects, not {.obj_type_friendly {first_scorer_chat}}.",
          call = call2("$score()")
        )
      }
    },

    check_metric_output = function() {
      for (metric_result in private$metric_results) {
        if (!is.numeric(metric_result$value)) {
          cli::cli_abort(
            c(
              "Each metric function must return a single numeric value",
              "{.fun {metric_result$name}} returned 
               {.obj_type_friendly {metric_result$value}}"
            ),
            call = call2("measure")
          )
        }
      }
    },

    cbind_solutions = function() {
      private$samples$result <- private$solutions$value$result
      private$samples$solver_chat <- private$solutions$value$solver_chat

      if ("solver_metadata" %in% names(private$solutions$value)) {
        private$samples$solver_metadata <- private$solutions$value$solver_metadata
      }

      invisible()
    },

    cbind_scores = function() {
      scorer_res <- private$scores$value
      private$samples$score <- scorer_res$score
      if ("scorer_chat" %in% names(scorer_res)) {
        private$samples$scorer_chat <- scorer_res$scorer_chat
      }
      if ("scorer_metadata" %in% names(scorer_res)) {
        private$samples$scorer_metadata <- scorer_res$scorer_metadata
      }

      private$samples$scorer <- private$scores$name
    },

    # For a named list of metric functions, apply each as `logged(fn_i)(scores)`
    apply_metrics = function() {
      private$metric_results <-
        purrr::map2(
          private$metric_fns,
          names(private$metric_fns),
          function(metric, metric_name) {
            # TODO: handle errors here? or should `logged()` do that?
            logged(metric, metric_name)(self$get_samples()$score)
          }
        )
    },

    # A default metric, mirroring the default accuracy in Inspect
    apply_naive_accuracy = function() {
      if (
        is.factor(self$get_samples()$score) &&
          (any(c("C", "I") %in% levels(self$get_samples()$score)))
      ) {
        # map factor to numeric for a simple accuracy (#51, #53)
        numeric_scores <- as.numeric(self$get_samples()$score) - 1
        if (any(is.na(numeric_scores))) {
          return()
        }
        numeric_scores <- numeric_scores / max(numeric_scores, na.rm = TRUE)
        private$metric_results <-
          list2(
            accuracy = logged(accuracy)(numeric_scores)
          )
      } else if (is.numeric(self$get_samples()$score)) {
        if (any(is.na(self$get_samples()$score))) {
          return()
        }
        private$metric_results <-
          list2(
            accuracy = logged(accuracy)(self$get_samples()$score)
          )
      }
    },

    # `slot` is one of "solver_token_usage" or "scorer_token_usage"
    # `env` is a function's execution environment
    track_token_usage = function(slot, env = caller_env()) {
      suppressMessages({
        initial_usage <- ellmer::token_usage()
      })

      withr::defer(
        {
          suppressMessages({
            final_usage <- ellmer::token_usage()
          })
          private[[slot]] <- diff_token_usage(initial_usage, final_usage)
        },
        envir = env
      )
    },

    # log working_time values by pre-computing durations from the Chat
    # objects before mapping over turns (#97)
    add_working_times = function(samples) {
      samples$solver_chat <- purrr::map(
        samples$solver_chat,
        add_working_times_to_turns,
        which = "solve",
        timestamps = private$timestamps,
        n = length(samples$solver_chat)
      )

      if ("scorer_chat" %in% names(samples)) {
        samples$scorer_chat <- purrr::map(
          samples$scorer_chat,
          add_working_times_to_turns,
          which = "score",
          timestamps = private$timestamps,
          n = length(samples$scorer_chat)
        )
      }

      samples
    },

    # log working_start values by estimating timings as if every turn in every
    # sample took the same amount of time (#112)
    #
    add_working_starts = function(samples) {
      samples$solver_chat <- add_working_start_to_turns(
        samples$solver_chat,
        which = "solve",
        timestamps = private$timestamps
      )

      if ("scorer_chat" %in% names(samples)) {
        samples$scorer_chat <- add_working_start_to_turns(
          samples$scorer_chat,
          which = "score",
          timestamps = private$timestamps
        )
      }

      samples
    },

    split_dots = function(dots) {
      solver_fn <- environment(private$solver)$fn
      scorer_fn <- environment(private$scorer)$fn

      solver_formals <- names(formals(solver_fn))
      scorer_formals <- names(formals(scorer_fn))

      solver_has_dots <- "..." %in% solver_formals
      scorer_has_dots <- "..." %in% scorer_formals

      solver_args <- list()
      scorer_args <- list()

      for (arg_name in names(dots)) {
        matches_solver <- arg_name %in% solver_formals
        matches_scorer <- arg_name %in% scorer_formals

        if (matches_solver) {
          solver_args[[arg_name]] <- dots[[arg_name]]
        }

        if (matches_scorer) {
          scorer_args[[arg_name]] <- dots[[arg_name]]
        }

        if (!matches_solver && !matches_scorer) {
          if (solver_has_dots) {
            solver_args[[arg_name]] <- dots[[arg_name]]
          }
          if (scorer_has_dots) {
            scorer_args[[arg_name]] <- dots[[arg_name]]
          }
          if (!solver_has_dots && !scorer_has_dots) {
            cli::cli_abort(
              "Argument {.arg {arg_name}} does not match any parameter in the solver or scorer functions.",
              call = call2("$eval()")
            )
          }
        }
      }

      list(solver = solver_args, scorer = scorer_args)
    },

    # The output of `logged(solver)(...)`
    solutions = NULL,

    # The output of `logged(scorer)(...)`.
    scores = NULL,

    # Argument supplied to `metrics` in `Task$new()` or `$set_metrics`.
    # Notably, not `logged()` directly--that function is applied in `apply_metrics()`
    metric_fns = NULL,

    # The output of `metrics(...)` (from directly above).
    metric_results = NULL,

    task_id = NULL,
    run_id = NULL,

    epochs = NULL
  )
)

#' @export
#' @importFrom cli cat_line format_inline col_grey
print.Task <- function(x, ...) {
  dataset_name <- x$.__enclos_env__$private$dataset_name

  cli::cat_line(cli::format_inline(
    "An evaluation {cli::col_blue('task')} {.field {dataset_name}}."
  ))

  if ("score" %in% names(x$get_samples())) {
    cli::cat_line(cli::format_inline(
      "Explore interactively with {.run .last_task$view()}."
    ))
  }

  invisible(x)
}


check_dataset <- function(dataset, call = caller_env()) {
  check_data_frame(dataset)

  required_cols <- c("input", "target")
  missing_cols <- required_cols[!required_cols %in% names(dataset)]

  if (length(missing_cols) > 0) {
    cli::cli_abort(
      "{.arg dataset} is missing required column{?s} {.field {missing_cols}}.",
      call = call
    )
  }

  invisible(dataset)
}

# Must be a named list of functions.
check_metrics <- function(metrics, call = caller_env()) {
  if (is.null(metrics)) {
    return()
  }

  if (
    !is.list(metrics) ||
      (is.list(metrics) && !is_named(metrics))
  ) {
    cli::cli_abort(
      "{.arg metrics} must be a named list of functions or NULL, 
       not {.obj_type_friendly {metrics}}",
      call = call
    )
  }

  for (metric in metrics) {
    check_function(metric, call = call)
  }

  invisible(metrics)
}

set_id_column <- function(dataset, call = caller_env()) {
  if ("id" %in% names(dataset)) {
    if (any(duplicated(dataset$id))) {
      cli::cli_abort(
        "Duplicated values found in the {.field id} column. Each ID must be unique.",
        call = call
      )
    }
  } else {
    dataset$id <- seq_len(nrow(dataset))
  }

  invisible(dataset)
}

join_epochs <- function(samples, epochs) {
  if (is.null(epochs)) {
    epochs <- 1L
  }
  if (abs(epochs - 1) < .1) {
    return(samples)
  }

  dplyr::inner_join(
    samples,
    data.frame(
      id = rep(samples$id, each = epochs),
      epoch = rep(seq_len(epochs), times = nrow(samples))
    ),
    by = "id"
  )
}

has_last_task <- function() {
  if (!"pkg:vitals" %in% search()) {
    return(FALSE)
  }

  exists(".last_task", as.environment("pkg:vitals"))
}

diff_token_usage <- function(before, after) {
  if (is.null(before)) {
    return(after)
  }

  res <- dplyr::left_join(
    after,
    before,
    by = c("provider", "model"),
    suffix = c("", "_before")
  )
  res <- dplyr::mutate(
    res,
    input = input - ifelse(is.na(input_before), 0, input_before)
  )
  res <- dplyr::mutate(
    res,
    output = output - ifelse(is.na(output_before), 0, output_before)
  )
  # if `price_before` is present, so will be `price` (#103)
  if ("price_before" %in% colnames(res)) {
    res <- dplyr::mutate(
      res,
      price = dplyr::if_else(
        is.na(price),
        NA,
        numeric_price(price) - numeric_price(price_before)
      )
    )
  }
  if ("price" %in% colnames(res)) {
    res <- dplyr::mutate(
      res,
      price = dplyr::if_else(is.na(price), NA, sprintf("$%.2f", price))
    )
  }
  res <- dplyr::select(res, provider, model, input, output, any_of("price"))

  dplyr::filter(res, input != 0 | output != 0)
}

bind_token_usage <- function(solver, scorer) {
  solver_token_usage <-
    dplyr::mutate(
      solver,
      source = "solver",
      .before = everything()
    )

  if (is.null(scorer)) {
    return(solver_token_usage)
  }

  dplyr::bind_rows(
    solver_token_usage,
    dplyr::mutate(
      scorer,
      source = "scorer",
      .before = everything()
    )
  )
}

numeric_price <- function(price) {
  result <- as.numeric(gsub("\\$", "", price))
  result[is.na(result)] <- 0
  result
}
