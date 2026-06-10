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
        create_model_event(turn, sample, timestamp = timestamps$solve$started_at)
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
          create_scoring_model_event(
            turn,
            sample,
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

create_model_event <- function(turn, sample, timestamp) {
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
      tool_results <- turn_tool_results(prev_turn)
      if (
        length(tool_results) > 0 &&
          length(tool_results) == length(prev_turn@contents)
      ) {
        return(purrr::map(tool_results, tool_result_message))
      } else {
        return(list(list(
          id = generate_id(),
          content = message_content_from_turn(prev_turn),
          source = "input",
          role = "user"
        )))
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

      return(list(message))
    }
  })
  input_messages <- purrr::list_flatten(input_messages)

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

  tools_list <- chat_tools_list(solver_chat)

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
        content = ensure_content_list(msg$content)
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
    config = drop_nulls(list(
      max_tokens = solver_chat$get_provider()@params$max_tokens
    )),
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
      request = drop_nulls(list(
        messages = request_messages,
        tools = tools_list,
        tool_choice = if (length(tools_list) > 0) {
          list(type = "auto")
        } else {
          "none"
        },
        model = solver_chat$get_model(),
        max_tokens = solver_chat$get_provider()@params$max_tokens,
        extra_headers = list(
          `x-irid` = generate_id()
        )
      )),
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
      parameters = list(
        type = "object",
        properties = c(),
        required = list(),
        additionalProperties = FALSE
      )
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

create_scoring_model_event <- function(turn, sample, timestamp) {
  scorer_chat <- sample$scorer_chat[[1]]
  turns <- scorer_chat$get_turns()
  previous_turns <- list()

  for (j in seq_along(turns)) {
    if (identical(turns[[j]], turn)) {
      break
    }
    previous_turns[[length(previous_turns) + 1]] <- turns[[j]]
  }

  input_messages <- lapply(previous_turns, function(prev_turn) {
    if (prev_turn@role == "user") {
      tool_results <- turn_tool_results(prev_turn)
      if (
        length(tool_results) > 0 &&
          length(tool_results) == length(prev_turn@contents)
      ) {
        return(purrr::map(tool_results, tool_result_message))
      } else {
        return(list(list(
          id = generate_id(),
          content = message_content_from_turn(prev_turn),
          source = "input",
          role = "user"
        )))
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

      return(list(message))
    }
  })
  input_messages <- purrr::list_flatten(input_messages)

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
  tools_list <- chat_tools_list(scorer_chat)

  output_message <- list(
    id = generate_id(),
    content = list(list(type = "text", text = turn@text)),
    source = "generate",
    role = "assistant"
  )

  if (has_tool_calls_in_turn) {
    output_message$tool_calls <- tool_calls_list
  }

  output_message$model <- scorer_chat$get_model()

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
            lapply(msg$content, function(item) {
              if (
                is.list(item) &&
                  identical(item$type, "image") &&
                  !is.null(item$source)
              ) {
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
        content = ensure_content_list(msg$content)
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
        processed_content <- if (is.list(msg$content)) {
          lapply(msg$content, function(item) {
            if (
              is.list(item) &&
                identical(item$type, "image") &&
                !is.null(item$source)
            ) {
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
    model = scorer_chat$get_model(),
    input = input_messages,
    tools = tools_list,
    tool_choice = if (length(tools_list) > 0) "auto" else "none",
    config = drop_nulls(list(
      max_tokens = scorer_chat$get_provider()@params$max_tokens
    )),
    output = list(
      model = scorer_chat$get_model(),
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
      request = drop_nulls(list(
        messages = request_messages,
        tools = tools_list,
        tool_choice = if (length(tools_list) > 0) {
          list(type = "auto")
        } else {
          "none"
        },
        model = scorer_chat$get_model(),
        max_tokens = scorer_chat$get_provider()@params$max_tokens,
        extra_headers = list(
          `x-irid` = generate_id()
        )
      )),
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
        model = scorer_chat$get_model(),
        role = "assistant",
        stop_reason = if (has_tool_calls_in_turn) "tool_use" else "end_turn",
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

  list(
    input_tokens = input_tokens,
    input_tokens_cache_write = 0L,
    input_tokens_cache_read = 0L,
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
