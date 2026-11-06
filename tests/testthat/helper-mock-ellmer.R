# Mocks the ellmer functions vitals uses to talk to models, following their
# documented contracts, so that tests don't depend on HTTP or on how ellmer
# builds requests. `respond(prompt, chat)` returns either the reply text or a
# list of turns to append after the user turn (e.g. to mock tool calls).
local_mocked_ellmer <- function(respond = mock_respond, env = caller_env()) {
  usage <- new.env()
  usage$tokens <- data.frame(
    provider = character(),
    model = character(),
    input = numeric(),
    output = numeric(),
    cached_input = numeric(),
    price = numeric()
  )

  local_mocked_bindings(
    parallel_chat = function(chat, prompts, ...) {
      lapply(prompts, mock_reply, chat = chat, respond = respond, usage = usage)
    },
    parallel_chat_structured = function(chat, prompts, type, ...) {
      replies <- lapply(prompts, function(prompt) {
        mock_reply(prompt, chat, respond, usage)$last_turn()@text
      })
      do.call(
        rbind,
        lapply(replies, function(reply) {
          as.data.frame(jsonlite::fromJSON(reply))
        })
      )
    },
    token_usage = function() usage$tokens,
    .package = "ellmer",
    .env = env
  )
}

# Answers addition questions, and passes anything graded by `model_graded_*()`.
mock_respond <- function(prompt, chat) {
  if (grepl("GRADE: $LETTER", prompt, fixed = TRUE)) {
    return("The submission meets the criterion.\nGRADE: C")
  }
  numbers <- regmatches(prompt, gregexpr("[0-9]+", prompt))[[1]]
  if (length(numbers) > 0) {
    return(as.character(sum(as.numeric(numbers))))
  }
  "Hello!"
}

# Replies with a JSON object for `parallel_chat_structured()` to parse.
mock_respond_structured <- function(prompt, chat) {
  if (grepl("GRADE: $LETTER", prompt, fixed = TRUE)) {
    return(mock_respond(prompt, chat))
  }
  as.character(jsonlite::toJSON(
    list(answer = mock_respond(prompt, chat)),
    auto_unbox = TRUE
  ))
}

mock_claude_chat <- function(...) {
  ellmer::chat_anthropic(
    model = "claude-sonnet-4-5",
    credentials = function() "fake-key",
    ...
  )
}

mock_reply <- function(prompt, chat, respond, usage) {
  reply <- respond(prompt, chat)
  if (is.character(reply)) {
    reply <- list(assistant_turn(
      contents = list(ellmer::ContentText(reply)),
      tokens = c(nchar(prompt), nchar(reply), 0),
      finish_reason = "success"
    ))
  }

  res <- chat$clone()
  res$set_turns(c(res$get_turns(), list(ellmer::UserTurn(prompt)), reply))
  for (turn in reply) {
    record_mock_tokens(usage, res, turn)
  }
  res
}

record_mock_tokens <- function(usage, chat, turn) {
  if (!inherits(turn, "ellmer::AssistantTurn")) {
    return(invisible())
  }
  tokens <- turn@tokens
  tokens[is.na(tokens)] <- 0
  provider <- chat$get_provider()@name
  model <- chat$get_model()

  i <- which(usage$tokens$provider == provider & usage$tokens$model == model)
  if (length(i) == 0) {
    usage$tokens <- rbind(
      usage$tokens,
      data.frame(
        provider = provider,
        model = model,
        input = tokens[1],
        output = tokens[2],
        cached_input = tokens[3],
        price = NA_real_
      )
    )
  } else {
    usage$tokens$input[i] <- usage$tokens$input[i] + tokens[1]
    usage$tokens$output[i] <- usage$tokens$output[i] + tokens[2]
    usage$tokens$cached_input[i] <- usage$tokens$cached_input[i] + tokens[3]
  }
  invisible()
}
