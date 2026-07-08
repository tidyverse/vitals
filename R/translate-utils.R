# model naming -----------------------------------------------------------------
# Inspect writes model strings as "provider/model" in eval$model, event-level
# model fields, and model_usage keys. The prefix is normalized so that
# `ellmer::chat("<prefix>/<model>")` can reconstruct a chat on read-back.
chat_provider_prefix <- function(chat) {
  name <- chat$get_provider()@name
  tolower(gsub("[^[:alnum:]]+", "_", name))
}

chat_provider_model <- function(chat) {
  paste0(chat_provider_prefix(chat), "/", chat$get_model())
}

# model usage ------------------------------------------------------------------
translate_to_model_usage <- function(chat) {
  tokens <- as.data.frame(chat$get_tokens())
  model <- chat_provider_model(chat)

  dots_list(
    !!model := list(
      input_tokens = sum(tokens$input, na.rm = TRUE),
      output_tokens = sum(tokens$output, na.rm = TRUE),
      total_tokens = sum(tokens$input, tokens$output, na.rm = TRUE),
      input_tokens_cache_write = 0,
      input_tokens_cache_read = sum(tokens$cached_input, na.rm = TRUE)
    )
  )
}

# given the list of solvers in a dataset, sum across all of their token usage
sum_model_usage <- function(solvers) {
  chat <- solvers[[1]]

  usage_per_solver <- lapply(
    solvers,
    function(chat) {
      translate_to_model_usage(chat)[[1]]
    }
  )
  res <- Reduce(function(x, y) Map(`+`, x, y), usage_per_solver)

  # TODO: ultimately, this needs to be per-model
  dots_list(!!chat_provider_model(chat) := res)
}

# output ----------------------------------------------------------------------
translate_to_output <- function(chat) {
  last_assistant_turn <- chat$last_turn()

  list(
    model = chat$get_model(),
    choices = translate_assistant_choices(last_assistant_turn),
    usage = translate_to_model_usage(chat)[[1]],
    time = turn_duration(last_assistant_turn)
  )
}

translate_assistant_choices <- function(turn) {
  list(list(
    message = list(
      id = generate_id(),
      content = assistant_message_content(turn),
      source = "generate",
      role = turn@role
    ),
    stop_reason = turn_stop_reason(turn)
  ))
}

# turn@json$stop_reason gives the provider-specific stop reason (e.g.
# 'end_turn'), but Inspect requires "Input should be 'stop', 'max_tokens',
# 'model_length', 'tool_calls', 'content_filter' or 'unknown'" (#7). ellmer
# standardizes finish_reason across providers; chats recorded before ellmer
# tracked finish_reason fall back to inferring from tool requests.
turn_stop_reason <- function(turn) {
  finish_reason <- tryCatch(turn@finish_reason, error = function(e) NULL)
  if (!is.null(finish_reason) && !is.na(finish_reason)) {
    return(switch(
      finish_reason,
      success = "stop",
      tool_use = "tool_calls",
      max_tokens = "max_tokens",
      stop_sequence = "stop",
      content_filter = "content_filter",
      context_window = "model_length",
      "unknown"
    ))
  }

  if (any(map_lgl(turn@contents, inherits, "ellmer::ContentToolRequest"))) {
    "tool_calls"
  } else {
    "stop"
  }
}

assistant_message_content <- function(turn) {
  blocks <- list()
  for (content in turn@contents) {
    if (inherits(content, "ellmer::ContentThinking")) {
      block <- list(type = "reasoning", reasoning = content@thinking)
      signature <- content@extra$signature
      if (!is.null(signature)) {
        block$signature <- signature
      }
      blocks <- c(blocks, list(block))
    } else if (inherits(content, "ellmer::ContentText")) {
      blocks <- c(blocks, list(list(type = "text", text = content@text)))
    }
  }

  if (!any(map_lgl(blocks, function(block) block$type == "text"))) {
    blocks <- c(blocks, list(list(type = "text", text = turn@text)))
  }

  blocks
}

# miscellaneous ----------------------------------------------------------------
message_content_from_turn <- function(turn) {
  contents <- turn@contents
  if (length(contents) == 0) {
    return(turn@text)
  }

  entries <- lapply(contents, translate_ellmer_content)
  if (length(entries) > 0) {
    only_text <- all(vapply(
      entries,
      function(entry) {
        is.list(entry) && identical(entry$type, "text")
      },
      logical(1)
    ))
    if (only_text) {
      return(turn@text)
    }
  }

  entries
}

translate_ellmer_content <- function(content) {
  if (inherits(content, "ellmer::ContentText")) {
    return(list(type = "text", text = content@text))
  }

  if (inherits(content, "ellmer::ContentImageInline")) {
    media_type <- content@type %||% "image/png"
    return(list(
      type = "image",
      image = paste0("data:", media_type, ";base64,", content@data)
    ))
  }

  if (inherits(content, "ellmer::ContentImageRemote")) {
    detail <- content@detail %||% "auto"
    result <- list(type = "image", image = content@url)
    if (nchar(detail) > 0) {
      result$detail <- detail
    }
    return(result)
  }

  fallback <- paste0(
    utils::capture.output(content),
    collapse = "\n"
  )
  list(type = "text", text = fallback)
}

tool_parameters_schema <- function(tool_def) {
  arguments <- tool_def@arguments
  if (is.null(arguments)) {
    return(list(
      type = "object",
      properties = c(),
      required = list(),
      additionalProperties = FALSE
    ))
  }
  type_to_schema(arguments)
}

type_to_schema <- function(type) {
  if (inherits(type, "ellmer::TypeObject")) {
    properties <- lapply(type@properties, type_to_schema)
    required <- map_lgl(type@properties, function(prop) prop@required)
    list(
      type = "object",
      properties = if (length(properties) == 0) c() else properties,
      required = as.list(names2(type@properties)[required]),
      additionalProperties = type@additional_properties
    )
  } else if (inherits(type, "ellmer::TypeEnum")) {
    list(
      type = "string",
      description = type@description %||% "",
      enum = as.list(type@values)
    )
  } else if (inherits(type, "ellmer::TypeArray")) {
    list(
      type = "array",
      description = type@description %||% "",
      items = type_to_schema(type@items)
    )
  } else if (inherits(type, "ellmer::TypeJsonSchema")) {
    type@json
  } else {
    list(type = type@type, description = type@description %||% "")
  }
}

is_content_list <- function(x) {
  if (!is.list(x) || length(x) == 0) {
    return(FALSE)
  }

  first <- x[[1]]
  is.list(first) && !is.null(first$type)
}

ensure_content_list <- function(content) {
  if (is_content_list(content)) {
    return(content)
  }

  list(list(type = "text", text = as.character(content)))
}

has_tool_calls <- function(turns) {
  any(sapply(turns, function(turn) {
    any(sapply(turn@contents, function(content) {
      inherits(content, "ellmer::ContentToolRequest")
    }))
  }))
}

eval_log_timestamp <- function(time = Sys.time()) {
  timestamp <- format(time, "%Y-%m-%dT%H:%M:%S%z")
  gsub("([+-][0-9]{2})([0-9]{2})$", "\\1:\\2", timestamp)
}

generate_id <- function(length = 22) {
  chars <- c(letters, LETTERS, 0:9)
  paste0(sample(chars, length, replace = TRUE), collapse = "")
}

eval_log_filename <- function(eval_log) {
  paste0(
    clean_filename_component(eval_log$eval$created),
    "_",
    clean_filename_component(eval_log$eval$task_id),
    ".json"
  )
}

clean_filename_component <- function(x) {
  gsub("[_/:]", "-", x)
}

results_scores <- function(name, metrics) {
  if (length(metrics) == 0) {
    metrics <- c()
  }
  list(list(
    name = name,
    scorer = name,
    params = structure(list(), names = character(0)),
    metrics = metrics
  ))
}

rename_metric_fields <- function(metrics) {
  metrics$params <- metrics$arguments
  metrics$arguments <- NULL
  metrics
}
