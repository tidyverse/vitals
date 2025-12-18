#' Convert a chat to a solver function
#'
#' @description
#' `generate()` is the simplest possible solver one might use with
#' vitals; it just passes its inputs to the supplied model and returns
#' its raw responses. The inputs are evaluated in parallel,
#' not in the sense of multiple R sessions, but in the sense of multiple,
#' asynchronous HTTP requests using [ellmer::parallel_chat()]. `generate()`'s output
#' can be passed directory to the `solver` argument of [Task]'s `$new()`
#' method.
#'
#' @param solver_chat An ellmer chat object, such as from
#'   [ellmer::chat_claude()], or a zero-argument function that returns one.
#'
#' @returns
#' The output of `generate()` is another function. That function takes in
#' a vector of `input`s, as well as a solver chat by the
#' name of `solver_chat` with the default supplied to `generate()` itself.
#'
#' See the documentation for the `solver` argument in [Task] for more
#' information on the return type.
#'
#' @seealso [generate_structured()] for structured output extraction.
#'
#' @inherit Task examples
#' @export
generate <- function(solver_chat = NULL) {
  chat <- solver_chat

  function(inputs, ..., solver_chat = chat) {
    if (is.function(solver_chat)) {
      ch <- solver_chat()
      check_inherits(ch, "Chat")
    } else {
      check_inherits(solver_chat, "Chat")
      ch <- solver_chat$clone()
    }

    res <- ellmer::parallel_chat(ch, as.list(inputs), ...)

    list(
      result = purrr::map_chr(res, function(c) c$last_turn()@text),
      solver_chat = res
    )
  }
}

#' Convert a chat to a solver function with structured output
#'
#' @description
#' `generate_structured()` is a variant of [generate()] that uses
#' [ellmer::parallel_chat_structured()] to extract structured data from
#' the model's responses. This allows you to define a schema for the
#' expected output using ellmer's `type_*()` functions.
#'
#' Because `parallel_chat_structured()` returns structured data rather than
#' Chat objects, `generate_structured()` creates synthetic Chat objects
#' for logging purposes. These "mock" chats contain the input and
#' JSON-serialized output as turns, but won't include actual token usage
#' or timing metadata from the API.
#'
#' The `result` field contains JSON-serialized strings for compatibility
#' with existing scorers. The raw structured data is available in
#' `$get_samples()$solver_metadata` after calling `$solve()` or `$eval()`.
#'
#' @inheritParams generate
#' @param type A type specification for the extracted data, created with
#'   ellmer's `type_*()` functions (e.g., [ellmer::type_object()],
#'   [ellmer::type_string()]). This defines the schema for the structured
#'   output.
#'
#' @inherit generate return
#'
#' @seealso [generate()] for unstructured output, [ellmer::type_object()] and
#'   related functions for defining type specifications.
#'
#' @examples
#' if (FALSE) {
#'   library(ellmer)
#'
#'   type_answer <- type_object(
#'     answer = type_string(
#'       "The author's first name, with no other formatting."
#'     )
#'   )
#'
#'   names <- tibble::tribble(
#'     ~input,                                  ~target,
#'     "Name's Josiah, how's it going?",        "Josiah",
#'     "I'm Lin, what's your name?",            "Lin",
#'     "My name is Em Fields, how about you?",  "Em"
#'   )
#'
#'   tsk <- Task$new(
#'     dataset = names,
#'     solver = generate_structured(
#'       solver_chat = chat_anthropic(model = "claude-sonnet-4-20250514"),
#'       type = type_answer
#'     ),
#'     scorer = detect_match("any")
#'   )
#'
#'   tsk$eval()
#'
#'   # the result is JSON-serialized for compatibility with scorers
#'   tsk$get_samples()$result
#'
#'   # raw structured data is available in solver_metadata
#'   tsk$get_samples()$solver_metadata
#'
#'   # solver_chat contains synthetic turns for logging
#'   tsk$get_samples()$solver_chat[[1]]
#' }
#' @export
generate_structured <- function(solver_chat = NULL, type = NULL) {
  chat <- solver_chat
  type_spec <- type

  function(inputs, ..., solver_chat = chat, type = type_spec) {
    if (is.function(solver_chat)) {
      ch <- solver_chat()
      check_inherits(ch, "Chat")
    } else {
      check_inherits(solver_chat, "Chat")
      ch <- solver_chat$clone()
    }

    res <- ellmer::parallel_chat_structured(
      ch,
      as.list(inputs),
      type = type,
      ...
    )

    res_per_input <- split_structured_result(res, length(inputs))

    solver_chats <- purrr::map2(
      inputs,
      res_per_input,
      mock_chat,
      solver_chat = ch
    )

    result_strings <- purrr::map_chr(
      res_per_input,
      function(x) as.character(jsonlite::toJSON(x, auto_unbox = TRUE))
    )

    list(
      result = result_strings,
      solver_chat = solver_chats,
      solver_metadata = res_per_input
    )
  }
}

split_structured_result <- function(res, n) {
  if (is.data.frame(res)) {
    lapply(seq_len(nrow(res)), function(i) res[i, , drop = FALSE])
  } else if (is.list(res) && length(res) == n) {
    res
  } else {
    rep(list(res), n)
  }
}

mock_chat <- function(input, result, solver_chat) {
  chat <- solver_chat$clone()

  user_turn <- ellmer::UserTurn(
    contents = list(ellmer::ContentText(as.character(input)))
  )

  result_json <- jsonlite::toJSON(result, auto_unbox = TRUE)
  assistant_turn <- ellmer::AssistantTurn(
    contents = list(ellmer::ContentText(as.character(result_json)))
  )

  chat$set_turns(list(user_turn, assistant_turn))

  chat
}
