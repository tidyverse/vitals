# model usage ------------------------------------------------------------------
translate_to_model_usage <- function(chat) {
  tokens <- as.data.frame(chat$get_tokens())
  model <- chat$get_model()

  dots_list(
    !!model := list(
      input_tokens = sum(tokens$tokens[tokens$role == "user"]),
      cache_creation_input_tokens = 0,
      cache_read_input_tokens = 0,
      output_tokens = sum(tokens$tokens[tokens$role == "assistant"]),
      total_tokens = sum(tokens$tokens)
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
  dots_list(!!chat$get_model() := res)
}

rename_token_fields <- function(input_list) {
  name_mapping <- c(
    "input_tokens" = "input_tokens",
    "output_tokens" = "output_tokens",
    "total_tokens" = "total_tokens",
    "cache_creation_input_tokens" = "input_tokens_cache_write",
    "cache_read_input_tokens" = "input_tokens_cache_read"
  )

  result <- list()
  for (name in names(input_list)) {
    if (name %in% names(name_mapping)) {
      result[[name_mapping[name]]] <- input_list[[name]]
    }
  }

  result
}

# output ----------------------------------------------------------------------
translate_to_output <- function(chat) {
  last_assistant_turn <- chat$last_turn()

  list(
    model = chat$get_model(),
    choices = translate_assistant_choices(last_assistant_turn),
    usage = rename_token_fields(translate_to_model_usage(chat)[[1]]),
    # TODO: is this the last time or the beginning time in Inspect?
    # Used to be `last_assistant_turn@completed`, but Inspect gives error:
    # samples.1.output.time: Input should be a valid number, unable to parse string as a number [type=float_parsing, input_value='2025-03-24 09:18:45', input_type=str]
    time = 1
  )
}

translate_assistant_choices <- function(turn) {
  text_contents <- first_text_contents(turn)
  list(list(
    message = list(
      id = generate_id(),
      content = list(list(
        type = "text",
        text = text_contents@text
      )),
      source = "generate",
      role = turn@role
    ),
    # turn@json$stop_reason gives the actual stop reason (often 'end_turn'), but
    # Inspect requires "Input should be 'stop', 'max_tokens', 'model_length',
    # 'tool_calls', 'content_filter' or 'unknown'" . (#7)
    stop_reason = "stop"
  ))
}

# miscellaneous ----------------------------------------------------------------
first_text_contents <- function(turn) {
  turn_contents <- turn@contents
  is_text <- vapply(turn_contents, inherits, logical(1), "ellmer::ContentText")
  turn_contents[[which(is_text)[1]]]
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
    gsub(":", "-", eval_log$eval$created),
    "_",
    gsub(" ", "-", gsub("_", "-", eval_log$eval$task)),
    "_",
    eval_log$eval$task_id,
    ".json"
  )
}

results_scores <- function(name, metrics) {
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
