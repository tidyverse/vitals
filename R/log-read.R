#' Read an eval log back into ellmer chats
#'
#' @description
#' Reconstruct the samples of a logged evaluation, including their
#' [ellmer::Chat] objects, from an eval log file written by [Task]'s `$log()`
#' method (or by Python Inspect).
#'
#' Chats are rebuilt from the log's message history: turn contents (text,
#' reasoning, images, tool calls, and tool results), per-turn token usage,
#' durations, and finish reasons are all restored. Information that is not
#' written to the log--most notably provider configuration beyond the model
#' name and the raw provider responses--cannot be recovered. Tool functions
#' are not serializable; pass `tools` to re-attach tool definitions by name.
#'
#' @param path Path to an eval log file, e.g. an element of the output of
#' `list.files(vitals_log_dir(), full.names = TRUE)`.
#' @param solver_chat Optional. An [ellmer::Chat] object to use as the base
#' for reconstructed solver chats. When `NULL`, the chat is constructed with
#' [ellmer::chat()] using the log's model string; supply this argument when
#' the log's provider requires additional configuration (e.g. a `base_url`).
#' @param scorer_chat Optional. Analogous to `solver_chat`, for the chats of
#' model-graded scorers.
#' @param tools Optional. A named list of [ellmer::tool()] definitions to
#' re-register on the reconstructed chats and attach to their tool calls.
#'
#' @returns A tibble with columns `id`, `epoch`, `input`, `target`, `result`,
#' `score`, and `solver_chat`, mirroring the output of [Task]'s
#' `$get_samples()` method. When the log contains model-graded scoring events,
#' a `scorer_chat` column is included as well.
#'
#' @examples
#' log_file <- system.file(
#'   "test/inspect/logs",
#'   "2025-03-24T10-39-36-05-00_simple-arithmetic_fQ9mYnqZFhtEuUenPpJgKL.json",
#'   package = "vitals"
#' )
#'
#' samples <- vitals_log_read(log_file)
#'
#' samples$solver_chat[[1]]
#'
#' @export
vitals_log_read <- function(
  path,
  solver_chat = NULL,
  scorer_chat = NULL,
  tools = list()
) {
  check_string(path)
  if (!file.exists(path)) {
    cli::cli_abort("{.arg path} does not exist: {.file {path}}.")
  }
  check_log_read_chat(solver_chat)
  check_log_read_chat(scorer_chat)

  log <- eval_log_read(path)

  call <- current_env()
  rows <- purrr::map(log$samples, function(sample) {
    log_sample_row(
      sample,
      model = log$eval$model,
      solver_chat = solver_chat,
      scorer_chat = scorer_chat,
      tools = tools,
      call = call
    )
  })

  res <- purrr::list_rbind(rows)
  if (all(purrr::map_lgl(res$scorer_chat, is.null))) {
    res$scorer_chat <- NULL
  }
  res
}

log_sample_row <- function(
  sample,
  model,
  solver_chat,
  scorer_chat,
  tools,
  call = rlang::caller_env()
) {
  attachments <- list2env(
    sample$attachments %||% list(),
    envir = new.env(parent = emptyenv())
  )
  sample <- resolve_attachments(sample, attachments)
  events <- split_events_at_scorer(sample$events %||% list())

  solver <- chat_from_log_messages(
    sample$messages,
    model = model,
    chat = solver_chat,
    tools = tools,
    model_events = log_model_events(events$solver),
    call = call
  )

  scorer <- scorer_chat_from_events(
    log_model_events(events$scorer),
    chat = scorer_chat,
    tools = tools,
    call = call
  )

  score <- if (length(sample$scores) > 0) sample$scores[[1]] else NULL

  tibble(
    id = sample$id,
    epoch = sample$epoch %||% 1L,
    input = log_input_text(sample$input),
    target = paste(unlist(sample$target), collapse = "\n"),
    result = score$answer %||% NA_character_,
    score = score$value %||% NA,
    solver_chat = list(solver),
    scorer_chat = list(scorer)
  )
}

# chat reconstruction ---------------------------------------------------------
chat_from_log_messages <- function(
  messages,
  model,
  chat = NULL,
  tools = list(),
  model_events = list(),
  call = rlang::caller_env()
) {
  res <- if (!is.null(chat)) {
    template <- chat$clone()
    template$set_model(sub("^[^/]+/", "", model))
    template
  } else {
    chat_from_model_string(model, call = call)
  }

  system_message <- purrr::detect(messages, function(message) {
    identical(message$role, "system")
  })
  if (!is.null(system_message)) {
    res$set_system_prompt(log_content_text(system_message$content))
  }

  if (length(tools) > 0) {
    res$set_tools(tools)
  }

  res$set_turns(turns_from_messages(
    messages,
    tools = tools,
    model_events = model_events
  ))

  res
}

chat_from_model_string <- function(model, call = rlang::caller_env()) {
  tryCatch(
    ellmer::chat(model),
    error = function(cnd) {
      cli::cli_abort(
        c(
          "Unable to construct a chat for model {.val {model}}.",
          "i" = "Supply a configured {.help [Chat](ellmer::Chat)} object \\
                 via the {.arg solver_chat} (or {.arg scorer_chat}) argument."
        ),
        parent = cnd,
        call = call
      )
    }
  )
}

turns_from_messages <- function(messages, tools = list(), model_events = list()) {
  events_by_message_id <- model_events_by_message_id(model_events)
  turns <- list()
  requests <- list()
  pending_results <- list()
  assistant_i <- 0L

  for (message in messages) {
    role <- message$role

    if (identical(role, "tool")) {
      pending_results <- c(
        pending_results,
        list(tool_result_from_message(message, requests))
      )
      next
    }

    if (length(pending_results) > 0) {
      turns <- c(turns, list(ellmer::UserTurn(contents = pending_results)))
      pending_results <- list()
    }

    if (identical(role, "system")) {
      next
    }

    if (identical(role, "user")) {
      turns <- c(
        turns,
        list(ellmer::UserTurn(contents = log_content_list(message$content)))
      )
      next
    }

    contents <- log_content_list(message$content)
    for (tool_call in message$tool_calls) {
      request <- ellmer::ContentToolRequest(
        id = tool_call$id,
        name = tool_call$`function`,
        arguments = tool_call$arguments,
        tool = tools[[tool_call$`function`]]
      )
      requests[[tool_call$id]] <- request
      contents <- c(contents, list(request))
    }

    assistant_i <- assistant_i + 1L
    event <- NULL
    if (!is.null(message$id)) {
      event <- events_by_message_id[[message$id]]
    }
    if (is.null(event) && assistant_i <= length(model_events)) {
      event <- model_events[[assistant_i]]
    }
    turns <- c(
      turns,
      list(assistant_turn_from_log(contents, event = event))
    )
  }

  if (length(pending_results) > 0) {
    turns <- c(turns, list(ellmer::UserTurn(contents = pending_results)))
  }

  turns
}

assistant_turn_from_log <- function(contents, event = NULL) {
  usage <- event$output$usage
  tokens <- c(
    usage$input_tokens %||% NA_real_,
    usage$output_tokens %||% NA_real_,
    usage$input_tokens_cache_read %||% NA_real_
  )

  stop_reason <- event$output$choices[[1]]$stop_reason

  ellmer::AssistantTurn(
    contents = contents,
    tokens = as.numeric(tokens),
    duration = as.numeric(event$output$time %||% event$working_time %||% NA),
    finish_reason = unname(
      stop_reason_to_finish_reason[stop_reason %||% "unknown"]
    )
  )
}

tool_result_from_message <- function(message, requests) {
  request <- requests[[message$tool_call_id %||% ""]] %||%
    ellmer::ContentToolRequest(
      id = message$tool_call_id %||% "",
      name = message$`function` %||% "",
      arguments = list()
    )

  if (!is.null(message$error)) {
    return(ellmer::ContentToolResult(
      error = message$error$message,
      request = request
    ))
  }

  value <- if (is.character(message$content)) {
    message$content
  } else {
    log_content_list(message$content)
  }

  ellmer::ContentToolResult(value = value, request = request)
}

# scorer chats are not stored as a message list, but the final scoring model
# event carries the full conversation: its input messages plus its output
scorer_chat_from_events <- function(
  model_events,
  chat,
  tools,
  call = rlang::caller_env()
) {
  if (length(model_events) == 0) {
    return(NULL)
  }

  last_event <- model_events[[length(model_events)]]
  output_message <- last_event$output$choices[[1]]$message
  messages <- c(last_event$input, list(output_message))

  chat_from_log_messages(
    messages,
    model = last_event$model,
    chat = chat,
    tools = tools,
    model_events = model_events,
    call = call
  )
}

# content conversion -----------------------------------------------------------
log_content_list <- function(content) {
  if (is.character(content)) {
    return(list(ellmer::ContentText(content)))
  }

  purrr::map(content, log_content_block)
}

log_content_block <- function(block) {
  type <- block$type %||% ""

  if (identical(type, "text")) {
    return(ellmer::ContentText(block$text))
  }

  if (identical(type, "reasoning")) {
    extra <- list()
    if (!is.null(block$signature)) {
      extra$signature <- block$signature
    }
    return(ellmer::ContentThinking(
      thinking = block$reasoning,
      extra = extra
    ))
  }

  if (identical(type, "image")) {
    return(content_image_url(block$image, detail = block$detail %||% "auto"))
  }

  ellmer::ContentText(
    as.character(jsonlite::toJSON(block, auto_unbox = TRUE))
  )
}

log_content_text <- function(content) {
  if (is.character(content)) {
    return(content)
  }

  texts <- purrr::keep(content, function(block) identical(block$type, "text"))
  paste(purrr::map_chr(texts, function(block) block$text), collapse = "\n")
}

log_input_text <- function(input) {
  if (is.character(input)) {
    return(input)
  }

  user_message <- purrr::detect(input, function(message) {
    identical(message$role %||% "user", "user")
  })
  if (is.null(user_message)) {
    return(NA_character_)
  }
  log_content_text(user_message$content)
}

# event handling ---------------------------------------------------------------
log_model_events <- function(events) {
  purrr::keep(events, function(event) identical(event$event, "model"))
}

model_events_by_message_id <- function(model_events) {
  res <- list()
  for (event in model_events) {
    id <- event$output$choices[[1]]$message$id
    if (!is.null(id)) {
      res[[id]] <- event
    }
  }
  res
}

# older Python Inspect logs (and vitals logs) mark the scorer with step
# events; recent Python Inspect writes span_begin/span_end instead
split_events_at_scorer <- function(events) {
  is_scorer_step <- purrr::map_lgl(events, function(event) {
    type <- event$type %||% ""
    (identical(event$event, "step") && identical(type, "scorer")) ||
      (identical(event$event, "span_begin") &&
        type %in% c("scorer", "scorers"))
  })

  first_scorer <- which(is_scorer_step)[1]
  if (is.na(first_scorer)) {
    return(list(solver = events, scorer = list()))
  }

  list(
    solver = events[seq_len(first_scorer - 1)],
    scorer = events[seq(first_scorer, length(events))]
  )
}

# attachment resolution ---------------------------------------------------------
resolve_attachments <- function(x, attachments) {
  if (is.character(x) && length(x) == 1 && startsWith(x, "attachment://")) {
    hash <- sub("attachment://", "", x, fixed = TRUE)
    return(get0(hash, envir = attachments, inherits = FALSE) %||% x)
  }

  if (is.list(x)) {
    return(lapply(x, resolve_attachments, attachments = attachments))
  }

  x
}

check_log_read_chat <- function(chat, call = rlang::caller_env()) {
  if (is.null(chat)) {
    return(invisible(NULL))
  }
  check_inherits(
    chat,
    "Chat",
    x_arg = rlang::caller_arg(chat),
    call = call
  )
}
