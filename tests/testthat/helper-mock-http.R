# Serves canned OpenAI chat completions to `mock_chat_template()` chats so that
# ellmer's real code runs without depending on the requests it builds.
# `respond(prompt, body)` returns reply text or a `mock_tool_call()`.
local_mocked_llm <- function(respond = mock_respond, env = caller_env()) {
  httr2::local_mocked_responses(
    function(req) {
      body <- httr2::req_get_body(req)
      mock_completion(respond(last_message_text(body), body))
    },
    env = env
  )
}

# Answers addition questions, and passes anything graded by `model_graded_*()`.
mock_respond <- function(prompt, body) {
  if (grepl("GRADE: $LETTER", prompt, fixed = TRUE)) {
    return("The submission meets the criterion.\nGRADE: C")
  }
  numbers <- regmatches(prompt, gregexpr("[0-9]+", prompt))[[1]]
  if (length(numbers) > 0) {
    return(as.character(sum(as.numeric(numbers))))
  }
  "Hello!"
}

mock_tool_call <- function(name, arguments = list(), id = "call_1") {
  arguments <- if (length(arguments) == 0) {
    "{}"
  } else {
    as.character(jsonlite::toJSON(arguments, auto_unbox = TRUE))
  }
  list(
    tool_calls = list(list(
      id = id,
      type = "function",
      `function` = list(name = name, arguments = arguments)
    ))
  )
}

# For provider-specific tests, where response formats are provider-defined:
# answers each input by appending canned turns to a clone of `chat`.
fixture_solver <- function(chat, reply = "4") {
  function(inputs) {
    solver_chat <- lapply(inputs, function(input) {
      res <- chat$clone()
      res$set_turns(list(
        ellmer::UserTurn(input),
        assistant_turn(
          contents = list(ellmer::ContentText(reply)),
          tokens = c(10, 5, 0),
          finish_reason = "success"
        )
      ))
      res
    })
    list(result = rep(reply, length(inputs)), solver_chat = solver_chat)
  }
}

mock_completion <- function(reply) {
  if (is.character(reply)) {
    message <- list(role = "assistant", content = reply)
    finish_reason <- "stop"
  } else {
    message <- c(list(role = "assistant"), reply)
    finish_reason <- "tool_calls"
  }

  httr2::response_json(
    body = list(
      id = "chatcmpl-mock",
      object = "chat.completion",
      choices = list(list(
        index = 0,
        message = message,
        finish_reason = finish_reason
      )),
      usage = list(prompt_tokens = 10, completion_tokens = 5, total_tokens = 15)
    )
  )
}

last_message_text <- function(body) {
  content <- body$messages[[length(body$messages)]]$content
  if (is.character(content)) {
    return(paste(content, collapse = "\n"))
  }
  texts <- purrr::map(content, "text")
  paste(unlist(texts), collapse = "\n")
}

# Replies with JSON for `parallel_chat_structured()` to parse.
mock_respond_structured <- function(prompt, body) {
  reply <- mock_respond(prompt, body)
  if (grepl("GRADE: $LETTER", prompt, fixed = TRUE)) {
    return(reply)
  }
  as.character(jsonlite::toJSON(list(answer = reply), auto_unbox = TRUE))
}

# Calls the tool `name` once, then replies with `reply` given its result.
mock_respond_tool <- function(name, reply, arguments = list()) {
  function(prompt, body) {
    last <- body$messages[[length(body$messages)]]
    if (identical(last$role, "tool")) {
      return(reply)
    }
    mock_tool_call(name, arguments)
  }
}
