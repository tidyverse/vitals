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

    # For a tool response turn
    if (
      length(turn@contents) == 1 &&
        inherits(turn@contents[[1]], "ellmer::ContentToolResult")
    ) {
      tool_result <- turn@contents[[1]]
      events <- c(
        events,
        create_tool_event(turn, tool_result, timestamps = timestamps)
      )
      next
    }

    # If we're at the last turn or this is a turn with tool requests
    if (
      i == length(solver_turns) ||
        any(sapply(
          turn@contents,
          function(ct) inherits(ct, "ellmer::ContentToolRequest")
        ))
    ) {
      events <- c(events, create_model_event(turn, sample))
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
    scorer_turn <- scorer_chat$last_turn()
    time_scorer <- timestamps$score$started_at

    events <- c(
      events,
      create_scorer_begin_event(
        time_scorer,
        attr(scorer_turn, "working_start")
      )
    )
    events <- c(
      events,
      create_scoring_model_event(
        scorer_turn,
        sample,
        time_scorer
      )
    )
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

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "sample_init",
    sample = list(
      input = input_string(sample$input[[1]]),
      target = sample$target,
      id = sample$id
    ),
    state = list(
      messages = list(
        list(
          id = user_message_id,
          content = input_string(sample$input[[1]]),
          source = "input",
          role = "user"
        )
      ),
      tools = list(),
      tool_choice = NULL,
      store = c(),
      output = list(
        model = sample$solver_chat[[1]]$get_model(),
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

create_use_tools_begin_event <- function(timestamp, working_start) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "begin",
    type = "solver",
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
          parameters = list(
            type = "object",
            properties = c(),
            required = list(),
            additionalProperties = FALSE
          )
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

create_use_tools_end_event <- function(timestamp, working_start) {
  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = working_start,
    event = "step",
    action = "end",
    type = "solver",
    name = "use_tools"
  ))
}

create_tool_event <- function(turn, tool_result, timestamps) {
  timestamp <- timestamps$solve$started_at
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

create_model_event <- function(turn, sample) {
  user_message_id <- generate_id()
  solver_chat <- sample$solver_chat[[1]]

  turns <- solver_chat$get_turns()
  previous_turns <- list()

  for (j in seq_along(turns)) {
    if (identical(turns[[j]], turn)) {
      break
    }
    previous_turns[[length(previous_turns) + 1]] <- turns[[j]]
  }

  input_messages <- lapply(previous_turns, function(prev_turn) {
    if (prev_turn@role == "user") {
      if (
        length(prev_turn@contents) == 1 &&
          inherits(prev_turn@contents[[1]], "ellmer::ContentToolResult")
      ) {
        tool_result <- prev_turn@contents[[1]]
        return(list(
          id = generate_id(),
          content = if (!is.null(tool_result@error)) {
            as.character(tool_result@error)
          } else {
            collapse_tool_result(tool_result)
          },
          role = "tool",
          tool_call_id = tool_result@request@id,
          `function` = tool_result@request@name
        ))
      } else {
        return(list(
          id = generate_id(),
          content = prev_turn@text,
          source = "input",
          role = "user"
        ))
      }
    } else {
      message <- list(
        id = generate_id(),
        content = list(list(type = "text", text = prev_turn@text)),
        source = "generate",
        role = "assistant"
      )

      tool_requests <- purrr::keep(prev_turn@contents, function(content) {
        inherits(content, "ellmer::ContentToolRequest")
      })

      if (length(tool_requests) > 0) {
        tool_calls <- lapply(tool_requests, function(req) {
          list(
            id = req@id,
            `function` = req@name,
            arguments = req@arguments
          )
        })

        message$tool_calls <- tool_calls
      }

      return(message)
    }
  })

  has_tool_calls_in_turn <- any(sapply(turn@contents, function(content) {
    inherits(content, "ellmer::ContentToolRequest")
  }))

  tool_calls_list <- list()
  if (has_tool_calls_in_turn) {
    tool_requests <- purrr::keep(turn@contents, function(content) {
      inherits(content, "ellmer::ContentToolRequest")
    })

    tool_calls_list <- lapply(tool_requests, function(req) {
      list(
        id = req@id,
        `function` = req@name,
        arguments = req@arguments
      )
    })
  }

  stop_reason <- ifelse(has_tool_calls_in_turn, "tool_calls", "stop")

  tools_list <- list()
  if (length(solver_chat$get_tools()) > 0) {
    tools <- solver_chat$get_tools()
    tools_list <- lapply(seq_along(tools), function(i) {
      tool <- tools[[i]]
      tool_name <- names(tools)[i]

      list(
        name = tool_name,
        description = tool@description,
        parameters = list(
          type = "object",
          properties = c(),
          required = list(),
          additionalProperties = FALSE
        )
      )
    })
  }

  output_message <- list(
    id = generate_id(),
    content = list(list(type = "text", text = turn@text)),
    source = "generate",
    role = "assistant"
  )

  if (has_tool_calls_in_turn) {
    output_message$tool_calls <- tool_calls_list
  }

  output_message$model <- solver_chat$get_model()

  request_messages <- lapply(input_messages, function(msg) {
    if (msg$role == "tool") {
      return(list(
        role = "user",
        content = list(list(
          tool_use_id = msg$tool_call_id,
          type = "tool_result",
          content = if (is.character(msg$content)) {
            list(list(type = "text", text = msg$content))
          } else {
            # Handle tool results that may contain image objects
            lapply(msg$content, function(item) {
              if (
                is.list(item) &&
                  identical(item$type, "image") &&
                  !is.null(item$source)
              ) {
                # Convert image object to ContentImage format
                list(
                  type = "image",
                  image = paste0(
                    "data:",
                    item$source$media_type,
                    ";base64,",
                    item$source$data
                  )
                )
              } else {
                item
              }
            })
          },
          # This depends specifically on previous helpers using
          # `as_character()` on conditions to extract error messages
          is_error = if (is.character(msg$content)) {
            grepl("Error in", msg$content)
          } else {
            FALSE
          }
        ))
      ))
    } else if (msg$role == "user") {
      return(list(
        role = "user",
        content = list(list(type = "text", text = msg$content))
      ))
    } else if (msg$role == "assistant") {
      if ("tool_calls" %in% names(msg)) {
        tool_use_elements <- lapply(msg$tool_calls, function(tc) {
          list(
            type = "tool_use",
            id = tc$id,
            name = tc$`function`,
            input = tc$arguments
          )
        })

        combined_content <- c(
          list(list(type = "text", text = msg$content[[1]]$text)),
          tool_use_elements
        )

        return(list(
          role = "assistant",
          content = combined_content
        ))
      } else {
        # Handle content that may contain image objects
        processed_content <- if (is.list(msg$content)) {
          lapply(msg$content, function(item) {
            if (
              is.list(item) &&
                identical(item$type, "image") &&
                !is.null(item$source)
            ) {
              # Convert image object to ContentImage format
              list(
                type = "image",
                image = paste0(
                  "data:",
                  item$source$media_type,
                  ";base64,",
                  item$source$data
                )
              )
            } else {
              item
            }
          })
        } else {
          msg$content
        }

        return(list(
          role = "assistant",
          content = processed_content
        ))
      }
    }
  })

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "model",
    model = solver_chat$get_model(),
    input = input_messages,
    tools = tools_list,
    tool_choice = if (length(tools_list) > 0) "auto" else "none",
    config = list(
      max_tokens = 4096
    ),
    output = list(
      model = solver_chat$get_model(),
      choices = list(
        list(
          message = output_message,
          stop_reason = stop_reason
        )
      ),
      usage = turn_tokens(turn),
      time = attr(turn, "working_time")
    ),
    call = list(
      request = list(
        messages = request_messages,
        tools = tools_list,
        tool_choice = if (length(tools_list) > 0) {
          list(type = "auto")
        } else {
          "none"
        },
        model = solver_chat$get_model(),
        max_tokens = 4096,
        extra_headers = list(
          `x-irid` = generate_id()
        )
      ),
      response = list(
        id = paste0("msg_", generate_id()),
        content = if (has_tool_calls_in_turn) {
          c(
            list(list(
              citations = NULL,
              text = turn@text,
              type = "text"
            )),
            lapply(tool_calls_list, function(tc) {
              list(
                id = tc$id,
                input = tc$arguments,
                name = tc$`function`,
                type = "tool_use"
              )
            })
          )
        } else {
          list(list(
            citations = NULL,
            text = turn@text,
            type = "text"
          ))
        },
        model = solver_chat$get_model(),
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

create_scoring_model_event <- function(turn, sample, timestamp) {
  user_id <- generate_id()
  scorer_chat <- sample$scorer_chat[[1]]
  scorer_user_turn <- scorer_chat$get_turns()[[1]]

  list(list(
    timestamp = events_timestamp(timestamp),
    working_start = attr(turn, "working_start"),
    event = "model",
    model = scorer_chat$get_model(),
    input = list(
      list(
        id = user_id,
        content = scorer_user_turn@text,
        role = "user"
      )
    ),
    tools = list(),
    tool_choice = "none",
    config = list(
      max_tokens = 4096
    ),
    output = list(
      model = scorer_chat$get_model(),
      choices = list(
        list(
          message = list(
            id = generate_id(),
            content = list(
              list(
                type = "text",
                text = turn@text
              )
            ),
            source = "generate",
            role = "assistant"
          ),
          stop_reason = "stop"
        )
      ),
      usage = turn_tokens(turn),
      time = attr(turn, "working_time")
    ),
    call = list(
      request = list(
        messages = list(
          list(
            role = "user",
            content = turn@text
          )
        ),
        tools = list(),
        model = scorer_chat$get_model(),
        max_tokens = 4096,
        extra_headers = list(
          `x-irid` = generate_id()
        )
      ),
      response = list(
        id = paste0("msg_", generate_id()),
        content = list(
          list(
            citations = NULL,
            text = turn@text,
            type = "text"
          )
        ),
        model = scorer_chat$get_model(),
        role = "assistant",
        stop_reason = "end_turn",
        stop_sequence = NULL,
        type = "message",
        usage = turn_tokens(turn),
        time = attr(turn, "working_time")
      )
    ),
    completed = events_timestamp(timestamp),
    working_time = attr(turn, "working_time")
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

# misc helpers -------------------------------------------------------------
# the events log the timestamp a bit differently than everywhere
# else in the log
events_timestamp <- function(time) {
  sub(
    pattern = "(\\d{2})(\\d{2})$",
    replacement = "\\1:\\2",
    x = format(Sys.time(), "%Y-%m-%dT%H:%M:%OS6%z")
  )
}

turn_tokens <- function(turn) {
  tokens_io <- turn@tokens

  list(
    input_tokens = tokens_io[1],
    input_tokens_cache_write = 0,
    input_tokens_cache_read = 0,
    output_tokens = tokens_io[2]
  )
}

# log working_time and working_starts values by pre-computing them from the Chat
# objects before mapping over turns (#97).
# `working_start` is the clock time when a turn started minus the clock time
# when the first chat in the solver or scorer started, in seconds.
# `working_time` is the duration of the turn (completed time of the turn
# minus the completed time of the turn preceding it).
#
# this was initially added to process `@completed` slots of turns. those were
# removed in ellmer 0.2.0, so we're temporarily filling them in with
# the average timing (#112)
add_working_times_to_turns <- function(chat, which, timestamps, n) {
  turns <- chat$get_turns()

  if (length(turns) < 2) {
    return(chat)
  }

  average_working_time <-
    as.numeric(difftime(
      timestamps[[which]]$completed_at,
      timestamps[[which]]$started_at,
      units = "secs"
    )) /
    (length(turns) * n)

  attr(turns[[1]], "working_time") <- NA_real_
  for (i in 2:length(turns)) {
    # TODO: revisit once durations are added to ellmer turns (#112)
    attr(turns[[i]], "working_time") <- average_working_time
  }

  chat$set_turns(turns)

  chat
}

# this was initially added to process `@completed` slots of turns. those were
# removed in ellmer 0.2.0, so we're temporarily filling them in with
# the estimated timing if every sample took the same amount of time (#112)
add_working_start_to_turns <- function(chats, which, timestamps) {
  total_duration <-
    as.numeric(difftime(
      timestamps[[which]]$completed_at,
      timestamps[[which]]$started_at,
      units = "secs"
    ))
  duration_per_chat <- total_duration / length(chats)
  current_working_start <- 0

  for (i in 1:length(chats)) {
    chat <- chats[[i]]
    chat_turns <- chat$get_turns()
    duration_per_turn <- duration_per_chat / (length(chat_turns) - 1)
    for (j in 1:length(chat_turns)) {
      attr(chat_turns[[j]], "working_start") <- current_working_start
      current_working_start <- current_working_start + duration_per_turn
    }
    chat$set_turns(chat_turns)
    chats[[i]] <- chat
  }

  chats
}
