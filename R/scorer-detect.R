#' Scoring with string detection
#'
#' @description
#' The following functions use string pattern detection to score model outputs.
#'
#' - `detect_includes()`: Determine whether the `target` from the sample
#' appears anywhere inside the model output. Can be case sensitive or
#' insensitive (defaults to the latter).
#' - `detect_match()`: Determine whether the `target` from the sample appears
#' at the beginning or end of model output (defaults to looking at the end).
#' Has options for ignoring case, white-space, and punctuation
#' (all are ignored by default).
#' - `detect_pattern()`: Extract matches of a pattern from the model response
#' and determine whether those matches also appear in `target`.
#' - `detect_answer()`: Scorer for model output that precedes answers with
#' "ANSWER: ". Can extract letters, words, or the remainder of the line.
#' - `detect_exact()`: Scorer which will normalize the text of the answer and
#' target(s) and perform an exact matching comparison of the text. This
#' scorer will return `CORRECT` when the answer is an exact match to one
#' or more targets.
#'
#' @param case_sensitive Logical, whether comparisons are case sensitive.
#' @param location Where to look for match: one of `"end"`, `"begin"`,
#' `"any"`, or `"exact"`. Defaults to `"end"`.
#' @param pattern Regular expression pattern to extract answer.
#' @param all Logical: for multiple captures, whether all must match.
#' @param format What to extract after `"ANSWER:"`: `"letter"`, `"word"`,
#' or `"line"`. Defaults to `"line"`.
#'
#' @seealso [model_graded_qa()] and [model_graded_fact()] for model-based
#' scoring.
#'
#' @returns
#' A function that scores model output based on string matching. Pass the
#' returned value to `$eval(scorer)`. See the documentation for the `scorer`
#' argument in [Task] for more information on the return type.
#'
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
#'     solver = generate(solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929")),
#'     scorer = detect_includes()
#'   )
#'
#'   # evaluate the task (runs solver and scorer)
#'   tsk$eval()
#' }
#'
#' @name scorer_detect
#' @export
detect_includes <- function(case_sensitive = FALSE) {
  check_bool(case_sensitive)

  function(samples) {
    results <- purrr::pmap(
      samples,
      function(...) {
        detect_includes_impl(
          list(...),
          case_sensitive = case_sensitive
        )
      }
    )

    list(
      score = factor(
        ifelse(purrr::map_lgl(results, "result"), "C", "I"),
        levels = c("I", "C"),
        ordered = TRUE
      ),
      scorer_metadata = purrr::map(results, "metadata")
    )
  }
}

detect_includes_impl <- function(sample, case_sensitive) {
  answer <- sample$result
  target <- sample$target

  if (!case_sensitive) {
    answer <- tolower(answer)
    target <- tolower(target)
  }

  result <- grepl(target, answer, fixed = TRUE)

  list(
    result = result,
    metadata = list(
      matched = result,
      answer = answer
    )
  )
}

#' @rdname scorer_detect
#' @export
detect_match <- function(
  location = c("end", "begin", "any", "exact"),
  case_sensitive = FALSE
) {
  location <- arg_match(location)
  check_bool(case_sensitive)

  function(samples) {
    results <- purrr::pmap(
      samples,
      function(...) {
        detect_match_impl(
          list(...),
          location = location,
          case_sensitive = case_sensitive
        )
      }
    )

    list(
      score = factor(
        ifelse(purrr::map_lgl(results, "result"), "C", "I"),
        levels = c("I", "C"),
        ordered = TRUE
      ),
      scorer_metadata = purrr::map(results, "metadata")
    )
  }
}

detect_match_impl <- function(sample, location, case_sensitive) {
  answer <- trimws(sample$result)
  target <- trimws(sample$target)

  if (!case_sensitive) {
    answer <- tolower(answer)
    target <- tolower(target)
  }

  result <- switch(
    location,
    begin = startsWith(answer, target),
    end = endsWith(answer, target),
    any = grepl(target, answer, fixed = TRUE),
    exact = answer == target,
    FALSE
  )

  list(
    result = result,
    metadata = list(
      matched = result,
      answer = answer
    )
  )
}

#' @rdname scorer_detect
#' @export
detect_pattern <- function(pattern, case_sensitive = FALSE, all = FALSE) {
  check_string(pattern)
  check_bool(case_sensitive)
  check_bool(all)

  function(samples) {
    results <- purrr::pmap(
      samples,
      function(...) {
        detect_pattern_impl(
          list(...),
          pattern = pattern,
          case_sensitive = case_sensitive,
          all = all
        )
      }
    )

    list(
      score = factor(
        ifelse(purrr::map_lgl(results, "result"), "C", "I"),
        levels = c("I", "C"),
        ordered = TRUE
      ),
      scorer_metadata = purrr::map(results, "metadata")
    )
  }
}

detect_pattern_impl <- function(sample, pattern, case_sensitive, all) {
  flags <- if (!case_sensitive) ignore.case = TRUE else NULL
  matches <- regexec(pattern, sample$result, perl = TRUE, flags)
  if (matches[[1]][1] == -1) {
    return(list(
      result = FALSE,
      metadata = list(
        matched = FALSE,
        answer = NA
      )
    ))
  }

  groups <- regmatches(sample$result, matches)[[1]][-1]
  target <- sample$target

  if (!case_sensitive) {
    groups <- tolower(groups)
    target <- tolower(target)
  }

  matched <- if (all) {
    all(groups %in% target)
  } else {
    any(groups %in% target)
  }

  list(
    result = matched,
    metadata = list(
      matched = matched,
      answer = groups[1]
    )
  )
}

#' @rdname scorer_detect
#' @export
detect_exact <- function(case_sensitive = FALSE) {
  check_bool(case_sensitive)

  function(samples) {
    results <- purrr::pmap(
      samples,
      function(...) {
        detect_exact_impl(
          list(...),
          case_sensitive = case_sensitive
        )
      }
    )

    list(
      score = factor(
        ifelse(purrr::map_lgl(results, "result"), "C", "I"),
        levels = c("I", "C"),
        ordered = TRUE
      ),
      scorer_metadata = purrr::map(results, "metadata")
    )
  }
}

detect_exact_impl <- function(sample, case_sensitive) {
  answer <- trimws(gsub("[[:punct:]]", "", sample$result))
  target <- trimws(gsub("[[:punct:]]", "", sample$target))

  if (!case_sensitive) {
    answer <- tolower(answer)
    target <- tolower(target)
  }

  matched <- answer == target

  list(
    result = matched,
    scorer = "exact",
    metadata = list(
      matched = matched,
      answer = answer
    )
  )
}

#' @rdname scorer_detect
#' @export
detect_answer <- function(format = c("line", "word", "letter")) {
  format <- arg_match(format)

  function(samples) {
    results <- purrr::pmap(
      samples,
      function(...) {
        detect_answer_impl(
          list(...),
          format = format
        )
      }
    )

    list(
      score = factor(
        ifelse(purrr::map_lgl(results, "result"), "C", "I"),
        levels = c("I", "C"),
        ordered = TRUE
      ),
      scorer_metadata = purrr::map(results, "metadata")
    )
  }
}

detect_answer_impl <- function(sample, format) {
  pattern <- switch(
    format,
    letter = "ANSWER:\\s*([A-Za-z])",
    word = "ANSWER:\\s*(\\w+)",
    line = "ANSWER:\\s*(.+)$",
    "ANSWER:\\s*(.+)$"
  )

  matches <- regexec(pattern, sample$result, perl = TRUE)
  if (matches[[1]][1] == -1) {
    return(list(
      result = FALSE,
      metadata = list(
        matched = FALSE,
        answer = NA
      )
    ))
  }

  answer <- regmatches(sample$result, matches)[[1]][2]
  matched <- tolower(trimws(answer)) == tolower(trimws(sample$target))

  list(
    result = matched,
    metadata = list(
      matched = matched,
      answer = answer
    )
  )
}
