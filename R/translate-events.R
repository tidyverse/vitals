# translates a sample to Inspect's "event" data structure. The high-level
# structure is something like:
# - Initialization (via the user turn)
# - Tool registration (if applicable)
# - Solver
# - Scorer
#
# TODO: how is the tool registered if it's in the scorer?
translate_to_events <- function(sample, timestamps) {
  events <- translate_events_initialize(sample, timestamps = timestamps)
  events <- translate_events_tool_use(events, sample, timestamps = timestamps)
  events <- translate_events_solver(events, sample, timestamps = timestamps)
  events <- translate_events_scorer(events, sample, timestamps = timestamps)
  events
}

# higher-level helpers ------------------------------------------------------
translate_events_initialize <- function(sample, timestamps) {
  solver_chat <- sample$solver_chat[[1]]
  solver_turns <- solver_chat$get_turns()

  time_user <- timestamps$solve$started_at
  last_working_start <- attr(
    solver_turns[[length(solver_turns)]],
    "working_start"
  )

  events <- list()
  events <- c(events, create_init_begin_event(time_user))
  events <- c(
    events,
    create_sample_init_event(solver_turns[[1]], sample, time_user)
  )
  events <- c(
    events,
    create_init_end_event(time_user, working_start = last_working_start)
  )

  events
}

translate_events_tool_use <- function(events, sample, timestamps) {
  solver_chat <- sample$solver_chat[[1]]
  solver_turns <- solver_chat$get_turns()

  time_user <- timestamps$solve$started_at

  if (has_tool_calls(solver_turns)) {
    events <- c(
      events,
      create_use_tools_begin_event(
        time_user,
        working_start = attr(solver_turns[[1]], "working_start")
      )
    )
    events <- c(events, create_tool_state_event(time_user, solver_chat))
    events <- c(
      events,
      create_use_tools_end_event(
        time_user,
        working_start = attr(
          solver_turns[[length(solver_turns)]],
          "working_start"
        )
      )
    )
  }

  events
}

translate_events_solver <- function(events, sample, timestamps) {
  solver_chat <- sample$solver_chat[[1]]
  solver_turns <- solver_chat$get_turns()
  solver_turn <- solver_chat$last_turn()

  time_user <- timestamps$solve$started_at
  time_solver <- timestamps$solve$started_at

  # From here, the solver logging goes turn-by-turn. For each turn, log
  # the content from that turn as well as the "state" (e.g. previous response
  # history) at that time. Tool calls are logged with a single event, where the
  # "model" event preceding it functions doubly as a user event calling the tool.
  events <- c(events, create_solver_begin_event(time_user))

  for (i in seq_along(solver_turns)) {
    if (i == 1) {
      # First turn is the user query, skip it
      next
    }

    turn <- solver_turns[[i]]

    # For a tool response turn (possibly carrying results of parallel calls)
    tool_results <- turn_tool_results(turn)
    if (
      length(tool_results) > 0 &&
        length(tool_results) == length(turn@contents)
    ) {
      for (tool_result in tool_results) {
        events <- c(
          events,
          create_tool_event(
            turn,
            tool_result,
            timestamp = timestamps$solve$started_at
          )
        )
      }
      next
    }

    if (turn@role == "assistant") {
      events <- c(
        events,
        create_model_event(
          turn,
          solver_chat,
          timestamp = timestamps$solve$started_at
        )
      )
    }
  }

  events <- c(
    events,
    create_solver_end_event(time_solver, attr(solver_turn, "working_start"))
  )

  events
}

translate_events_scorer <- function(events, sample, timestamps = timestamps) {
  if ("scorer_chat" %in% names(sample)) {
    scorer_chat <- sample$scorer_chat[[1]]
    scorer_turns <- scorer_chat$get_turns()
    scorer_turn <- scorer_chat$last_turn()
    time_scorer <- timestamps$score$started_at

    if (has_tool_calls(scorer_turns)) {
      events <- c(
        events,
        create_use_tools_begin_event(
          time_scorer,
          attr(scorer_turns[[1]], "working_start") %||% 0,
          type = "scorer"
        )
      )
      events <- c(events, create_tool_state_event(time_scorer, scorer_chat))

      tool_result_turns <- purrr::keep(scorer_turns, function(turn) {
        results <- turn_tool_results(turn)
        length(results) > 0 && length(results) == length(turn@contents)
      })

      for (turn in tool_result_turns) {
        for (tool_result in turn_tool_results(turn)) {
          events <- c(
            events,
            create_tool_event(
              turn,
              tool_result,
              timestamp = timestamps$score$started_at
            )
          )
        }
      }

      events <- c(
        events,
        create_use_tools_end_event(
          time_scorer,
          attr(scorer_turns[[length(scorer_turns)]], "working_start") %||% 0,
          type = "scorer"
        )
      )
    }

    events <- c(
      events,
      create_scorer_begin_event(
        time_scorer,
        attr(scorer_turn, "working_start")
      )
    )

    assistant_turns <- purrr::keep(
      scorer_turns,
      function(turn) turn@role == "assistant"
    )

    for (turn in assistant_turns) {
      has_tool_request <- any(vapply(
        turn@contents,
        inherits,
        logical(1),
        "ellmer::ContentToolRequest"
      ))

      if (identical(turn, scorer_turn) || has_tool_request) {
        events <- c(
          events,
          create_model_event(
            turn,
            scorer_chat,
            time_scorer
          )
        )
      }
    }

    events <- c(events, create_score_event(scorer_turn, sample, time_scorer))
    events <- c(
      events,
      create_scorer_end_event(
        time_scorer,
        attr(scorer_turn, "working_start")
      )
    )
  }

  events
}

# event-specific helpers ------------------------------------------------------
create_init_begin_event <- function(timestamp) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = 0,
    event = "step",
    action = "begin",
    name = "init"
  ))
}

create_sample_init_event <- function(turn, sample, timestamp) {
  user_message_id <- generate_id()
  message_content <- message_content_from_turn(turn)
  sample_input <- if (is_content_list(message_content)) {
    list(list(
      content = message_content,
      source = "input",
      role = "user"
    ))
  } else {
    message_content
  }

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "sample_init",
    sample = list(
      input = sample_input,
      target = sample$target,
      id = sample$id
    ),
    state = list(
      messages = list(
        list(
          id = user_message_id,
          content = message_content,
          source = "input",
          role = "user"
        )
      ),
      tools = list(),
      tool_choice = NULL,
      store = c(),
      output = list(
        model = chat_provider_model(sample$solver_chat[[1]]),
        choices = list()
      ),
      completed = FALSE,
      metadata = c()
    )
  ))
}

create_init_end_event <- function(timestamp, working_start) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "end",
    name = "init"
  ))
}

create_use_tools_begin_event <- function(
  timestamp,
  working_start,
  type = "solver"
) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "begin",
    type = type,
    name = "use_tools"
  ))
}

create_tool_state_event <- function(timestamp, chat) {
  tools_list <- list()

  if (length(chat$get_tools()) > 0) {
    tool_defs <- chat$get_tools()

    for (i in seq_along(tool_defs)) {
      tool_def <- tool_defs[[i]]
      tool_name <- names(tool_defs)[i]

      tool_info <- list(
        op = "add",
        path = paste0("/tools/", i - 1),
        value = list(
          name = tool_name,
          description = tool_def@description,
          parameters = tool_parameters_schema(tool_def)
        )
      )

      tools_list <- append(tools_list, list(tool_info))
    }
  }

  tools_list <- append(
    tools_list,
    list(list(
      op = "replace",
      path = "/tool_choice",
      value = "auto"
    ))
  )

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(chat$get_turns()[[1]], "working_start"),
    event = "state",
    changes = tools_list
  ))
}

create_use_tools_end_event <- function(
  timestamp,
  working_start,
  type = "solver"
) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "end",
    type = type,
    name = "use_tools"
  ))
}

create_tool_event <- function(turn, tool_result, timestamp) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "tool",
    type = "function",
    id = tool_result@request@id,
    `function` = tool_result@request@name,
    arguments = tool_result@request@arguments,
    result = if (!is.null(tool_result@error)) {
      as.character(tool_result@error)
    } else {
      collapse_tool_result(tool_result)
    },
    events = list(),
    completed = events_timestamp(timestamp),
    working_time = attr(turn, "working_time")
  ))
}

create_solver_begin_event <- function(timestamp) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = 0,
    event = "step",
    action = "begin",
    type = "solver",
    name = "generate"
  ))
}

create_model_event <- function(turn, chat, timestamp) {
  turns <- chat$get_turns()
  previous_turns <- list()

  for (j in seq_along(turns)) {
    if (identical(turns[[j]], turn)) {
      break
    }
    previous_turns[[length(previous_turns) + 1]] <- turns[[j]]
  }

  input_messages <- purrr::list_flatten(
    lapply(previous_turns, event_input_message)
  )

  tool_calls_list <- turn_tool_calls(turn)
  has_tool_calls_in_turn <- length(tool_calls_list) > 0

  tools_list <- chat_tools_list(chat)

  output_message <- list(
    id = generate_id(),
    content = assistant_message_content(turn),
    source = "generate",
    role = "assistant"
  )

  if (has_tool_calls_in_turn) {
    output_message$tool_calls <- tool_calls_list
  }

  output_message$model <- chat$get_model()

  request_messages <- lapply(input_messages, event_request_message)

  response_content <- c(
    request_content_blocks(assistant_message_content(turn)),
    lapply(tool_calls_list, function(tc) {
      list(
        id = tc$id,
        input = tc$arguments,
        name = tc$`function`,
        type = "tool_use"
      )
    })
  )

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "model",
    model = chat_provider_model(chat),
    input = input_messages,
    tools = tools_list,
    tool_choice = if (length(tools_list) > 0) "auto" else "none",
    config = drop_nulls(list(
      max_tokens = chat$get_provider()@params$max_tokens
    )),
    output = list(
      model = chat$get_model(),
      choices = list(
        list(
          message = output_message,
          stop_reason = turn_stop_reason(turn)
        )
      ),
      usage = turn_tokens(turn),
      time = attr(turn, "working_time")
    ),
    call = list(
      request = drop_nulls(list(
        messages = request_messages,
        tools = tools_list,
        tool_choice = if (length(tools_list) > 0) {
          list(type = "auto")
        } else {
          "none"
        },
        model = chat$get_model(),
        max_tokens = chat$get_provider()@params$max_tokens,
        extra_headers = list(
          `x-irid` = generate_id()
        )
      )),
      response = list(
        id = paste0("msg_", generate_id()),
        content = response_content,
        model = chat$get_model(),
        role = "assistant",
        stop_reason = if (has_tool_calls_in_turn) "tool_use" else "end_turn",
        stop_sequence = NULL,
        type = "message",
        usage = turn_tokens(turn)
      ),
      time = attr(turn, "working_time")
    ),
    completed = events_timestamp(timestamp),
    working_time = attr(turn, "working_time")
  ))
}

event_input_message <- function(prev_turn) {
  if (prev_turn@role == "user") {
    tool_results <- turn_tool_results(prev_turn)
    if (
      length(tool_results) > 0 &&
        length(tool_results) == length(prev_turn@contents)
    ) {
      return(purrr::map(tool_results, tool_result_message))
    }
    return(list(list(
      id = generate_id(),
      content = message_content_from_turn(prev_turn),
      source = "input",
      role = "user"
    )))
  }

  message <- list(
    id = generate_id(),
    content = assistant_message_content(prev_turn),
    source = "generate",
    role = "assistant"
  )

  tool_calls <- turn_tool_calls(prev_turn)
  if (length(tool_calls) > 0) {
    message$tool_calls <- tool_calls
  }

  list(message)
}

turn_tool_calls <- function(turn) {
  tool_requests <- purrr::keep(turn@contents, function(content) {
    inherits(content, "ellmer::ContentToolRequest")
  })

  lapply(tool_requests, function(req) {
    list(
      id = req@id,
      `function` = req@name,
      arguments = req@arguments
    )
  })
}

# reconstructs an Anthropic-style request payload from the message list, for
# display in the viewer's API view
event_request_message <- function(msg) {
  if (msg$role == "tool") {
    return(list(
      role = "user",
      content = list(list(
        tool_use_id = msg$tool_call_id,
        type = "tool_result",
        content = request_content_blocks(msg$content),
        is_error = !is.null(msg$error)
      ))
    ))
  }

  if (msg$role == "user") {
    return(list(
      role = "user",
      content = ensure_content_list(msg$content)
    ))
  }

  tool_use_elements <- lapply(msg$tool_calls, function(tc) {
    list(
      type = "tool_use",
      id = tc$id,
      name = tc$`function`,
      input = tc$arguments
    )
  })

  list(
    role = "assistant",
    content = c(request_content_blocks(msg$content), tool_use_elements)
  )
}

request_content_blocks <- function(content) {
  if (is.character(content)) {
    return(list(list(type = "text", text = content)))
  }

  lapply(content, function(block) {
    if (identical(block$type, "reasoning")) {
      list(type = "thinking", thinking = block$reasoning)
    } else {
      block
    }
  })
}

chat_tools_list <- function(chat) {
  if (length(chat$get_tools()) == 0) {
    return(list())
  }

  tools <- chat$get_tools()
  lapply(seq_along(tools), function(i) {
    tool <- tools[[i]]
    tool_name <- names(tools)[i]

    list(
      name = tool_name,
      description = tool@description,
      parameters = tool_parameters_schema(tool)
    )
  })
}

create_solver_end_event <- function(timestamp, working_start) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "end",
    type = "solver",
    name = "generate"
  ))
}

create_scorer_begin_event <- function(timestamp, working_start) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "begin",
    type = "scorer",
    name = "model_graded_qa"
  ))
}

create_score_event <- function(turn, sample, timestamp) {
  scorer_user_turn <- sample$scorer_chat[[1]]$get_turns()[[1]]

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "score",
    score = list(
      value = sample$score,
      answer = as.character(sample$result),
      explanation = turn@text,
      metadata = list(
        grading = list(
          list(
            id = generate_id(),
            content = scorer_user_turn@text,
            role = "user"
          ),
          list(
            id = generate_id(),
            content = list(
              list(
                type = "text",
                text = turn@text
              )
            ),
            source = "generate",
            role = "assistant"
          )
        )
      )
    ),
    target = sample$target,
    intermediate = FALSE
  ))
}

create_scorer_end_event <- function(timestamp, working_start) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "end",
    type = "scorer",
    name = "model_graded_qa"
  ))
}

drop_nulls <- function(x) {
  x[!vapply(x, is.null, logical(1))]
}

# misc helpers -------------------------------------------------------------
# the events log the timestamp a bit differently than everywhere
# else in the log
events_timestamp <- function(time) {
  sub(
    pattern = "(\\d{2})(\\d{2})$",
    replacement = "\\1:\\2",
    x = format(time, "%Y-%m-%dT%H:%M:%OS6%z")
  )
}

turn_tokens <- function(turn) {
  tokens_io <- turn@tokens

  input_tokens <- if (is.na(tokens_io[1])) 0L else as.integer(tokens_io[1])
  output_tokens <- if (is.na(tokens_io[2])) 0L else as.integer(tokens_io[2])
  cached_tokens <- if (length(tokens_io) < 3 || is.na(tokens_io[3])) {
    0L
  } else {
    as.integer(tokens_io[3])
  }

  list(
    input_tokens = input_tokens,
    input_tokens_cache_write = 0L,
    input_tokens_cache_read = cached_tokens,
    output_tokens = output_tokens
  )
}

turn_duration <- function(turn) {
  duration <- 0
  if (inherits(turn, "ellmer::AssistantTurn")) {
    if (!is.na(turn@duration)) {
      duration <- turn@duration
    }
  }
  duration
}

# log working_time values by extracting them from the Turn @duration slots (#115).
# `working_time` is the duration of the turn in seconds. User turns have NA duration,
# assistant turns have the actual request duration as measured by httr2.
add_working_times_to_turns <- function(chat, which, timestamps, n) {
  turns <- chat$get_turns()

  if (length(turns) < 2) {
    return(chat)
  }

  for (i in seq_along(turns)) {
    attr(turns[[i]], "working_time") <- turn_duration(turns[[i]])
  }

  chat$set_turns(turns)

  chat
}

# log working_start values by accumulating turn durations (#115).
# `working_start` is the clock time when a turn started minus the clock time
# when the first chat started, in seconds. This is computed by accumulating
# the @duration values from previous turns.
add_working_start_to_turns <- function(chats, which, timestamps) {
  current_working_start <- 0

  for (i in seq_along(chats)) {
    chat <- chats[[i]]
    chat_turns <- chat$get_turns()

    for (j in seq_along(chat_turns)) {
      attr(chat_turns[[j]], "working_start") <- current_working_start
      current_working_start <- current_working_start + turn_duration(chat_turns[[j]])
    }

    chat$set_turns(chat_turns)
    chats[[i]] <- chat
  }

  chats
}
