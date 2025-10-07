#' Model-based scoring
#'
#' @description
#' Model-based scoring makes use of a model to score output from a solver.
#'
#' * `model_graded_qa()` scores how well a solver answers a question/answer task.
#' * `model_graded_fact()` determines whether a solver includes a given fact
#' in its response.
#'
#' The two scorers are quite similar in their implementation, but use a different
#' default `template` to evaluate correctness.
#'
#' @param template Grading template to use--a `glue()` string which will take
#' substitutions `input`, `answer`, `criterion`, `instructions`.
#' @param instructions Grading instructions.
#' @param grade_pattern A regex pattern to extract the final grade from the
#' judge model's response.
#' @param partial_credit Whether to allow partial credit.
#' @param scorer_chat An ellmer chat used to grade the model output, e.g.
#' [ellmer::chat_anthropic()].
#'
#' @returns
#' A function that will grade model responses according to the given instructions.
#' See [Task]'s `scorer` argument for a description of the returned function.
#' The functions that `model_graded_qa()` and `model_graded_fact()` output
#' can be passed directly to `$eval()`.
#'
#' See the documentation for the `scorer` argument in [Task] for more
#' information on the return type.
#'
#' @seealso [scorer_detect] for string detection-based scoring.
#'
#' @examples
#' # Quality assurance -----------------------------
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
#'   tsk <- Task$new(
#'     dataset = simple_addition,
#'     solver = generate(solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929")),
#'     scorer = model_graded_qa()
#'   )
#'
#'   tsk$eval()
#' }
#'
#' # Factual response -------------------------------
#' if (!identical(Sys.getenv("ANTHROPIC_API_KEY"), "")) {
#'   # set the log directory to a temporary directory
#'   withr::local_envvar(VITALS_LOG_DIR = withr::local_tempdir())
#'
#'   library(ellmer)
#'   library(tibble)
#'
#'   r_history <- tibble(
#'     input = c(
#'       "Who created the R programming language?",
#'       "In what year was version 1.0 of R released?"
#'     ),
#'     target = c("Ross Ihaka and Robert Gentleman.", "2000.")
#'   )
#'
#'   tsk <- Task$new(
#'     dataset = r_history,
#'     solver = generate(solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929")),
#'     scorer = model_graded_fact()
#'   )
#'
#'   tsk$eval()
#' }
#'
#' @name scorer_model
#' @export
model_graded_qa <- function(
  template = NULL,
  instructions = NULL,
  grade_pattern = "(?i)GRADE\\s*:\\s*([CPI])(.*)$",
  partial_credit = FALSE,
  scorer_chat = NULL
) {
  ch <- scorer_chat

  function(samples, ..., scorer_chat = ch) {
    model_graded_qa_impl(
      samples = samples,
      template = template,
      instructions = instructions,
      grade_pattern = grade_pattern,
      partial_credit = partial_credit,
      scorer_chat = scorer_chat
    )
  }
}

model_graded_qa_impl <- function(
  samples,
  template = NULL,
  instructions = NULL,
  grade_pattern = "(?i)GRADE\\s*:\\s*([CPI])(.*)$",
  partial_credit = FALSE,
  scorer_chat = NULL
) {
  template <- template %||% qa_default_template()
  instructions <- instructions %||% qa_default_instructions(partial_credit)

  prompts <- purrr::map_chr(seq_len(nrow(samples)), function(i) {
    qa_format_prompt(
      template,
      samples$input[i],
      samples$result[i],
      samples$target[i],
      instructions
    )
  })

  if (is.null(scorer_chat)) {
    scorer_chat <- solver_chat(samples[1, ])
  }

  scorer_chat <- scorer_chat$clone()
  responses <- ellmer::parallel_chat(scorer_chat, as.list(prompts))

  grades <- purrr::map_chr(responses, function(response_chat) {
    response_text <- response_chat$last_turn()@text
    qa_extract_grade(response_text, grade_pattern, partial_credit)
  })

  scores <- process_grades(grades, partial_credit)

  metadata <- purrr::map(seq_along(prompts), function(i) {
    list(
      prompt = prompts[i],
      response = responses[[i]]$last_turn()@text,
      grade_pattern = grade_pattern
    )
  })

  list(
    score = scores,
    scorer_chat = responses,
    scorer_metadata = metadata
  )
}

qa_format_prompt <- function(template, input, output, target, instructions) {
  glue::glue(
    template,
    input = input,
    answer = output,
    criterion = target,
    instructions = instructions
  )
}

qa_extract_grade <- function(response, pattern, partial_credit = FALSE) {
  grade_letter <- regmatches(
    response,
    regexec(pattern, response, perl = TRUE)
  )[[1]][2]

  if (is.na(grade_letter)) {
    return(NA)
  }

  toupper(grade_letter)
}

process_grades <- function(grades, partial_credit) {
  unique_grades <- unique(grades)
  is_ipc_grading <- (
    any(c("I", "C") %in% unique_grades) &&
    all(unique_grades %in% c("I", "P", "C"))
  )

  if (!is_ipc_grading) {
    return(grades)
  }

  if (partial_credit) {
    factor(
      grades,
      levels = c("I", "P", "C"),
      ordered = TRUE
    )
  } else {
    factor(
      grades,
      levels = c("I", "C"),
      ordered = TRUE
    )
  }
}

qa_default_instructions <- function(partial_credit = FALSE) {
  partial_letter <- if (partial_credit) ", P, or " else " or "
  partial_prompt <- if (partial_credit) {
    '"P" for partially correct answers,'
  } else {
    ""
  }

  glue::glue(
    "After assessing the submitted answer, reply with 'GRADE: $LETTER' where
    LETTER is one of C{partial_letter}I.
    Please choose ONE option: either 'C' for correct answers, {partial_prompt}
    or 'I' for incorrect answers.
    First explain your reasoning, then end with GRADE: $LETTER.
    Do not format the grading string and do not include any punctuation or
    exposition after it."
  )
}

# based on https://github.com/UKGovernmentBEIS/inspect_ai/blob/f60a6ff8502fa43ef1b9a7a905eab2a21608f1c1/src/inspect_ai/scorer/_model.py#L206
qa_default_template <- function() {
  "You are assessing a submitted answer on a given task based on a criterion.
  [BEGIN DATA]
  ***
  [Task]: {input}
  ***
  [Submission]: {answer}
  ***
  [Criterion]: {criterion}
  ***
  [END DATA]
  Does the submission meet the criterion?
  {instructions}"
}

#' @rdname scorer_model
#' @export
model_graded_fact <- function(
  template = NULL,
  instructions = NULL,
  grade_pattern = "(?i)GRADE\\s*:\\s*([CPI])(.*)$",
  partial_credit = FALSE,
  scorer_chat = NULL
) {
  ch <- scorer_chat

  function(samples, scorer_chat = ch) {
    model_graded_qa_impl(
      samples = samples,
      template = template %||% fact_default_template(),
      instructions = instructions,
      grade_pattern = grade_pattern,
      partial_credit = partial_credit,
      scorer_chat = scorer_chat
    )
  }
}

fact_default_template <- function() {
  "You are comparing a submitted answer to an expert answer on a given question.
  [BEGIN DATA]
  ************
  [Question]: {input}
  ************
  [Expert]: {criterion}
  ************
  [Submission]: {answer}
  ************
  [END DATA]
  Compare the factual content of the submitted answer with the expert answer.
  Ignore any differences in style, grammar, or punctuation.
  Does the submission contain the content in the expert answer?
  {instructions}"
}
