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
#' @inherit Task examples
#' @export
generate <- function(solver_chat = NULL) {
  chat <- solver_chat

  function(inputs, ..., solver_chat = chat) {
    if (is.function(solver_chat)) {
      solver_chat <- solver_chat()
    }
    check_inherits(solver_chat, "Chat")

    ch <- solver_chat$clone()
    res <- ellmer::parallel_chat(ch, as.list(inputs), ...)

    list(
      result = purrr::map_chr(res, function(c) c$last_turn()@text),
      solver_chat = res
    )
  }
}
