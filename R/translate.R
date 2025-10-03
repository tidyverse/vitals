eval_log <- function(
  eval = translate_to_eval(),
  plan = translate_to_plan(),
  results = translate_to_results(),
  stats = translate_to_stats(),
  samples
) {
  res <-
    list(
      version = 2L,
      status = "success",
      eval = eval,
      plan = plan,
      results = results,
      stats = stats,
      samples = samples
    )

  structure(res, class = c("eval_log", class(res)))
}

# top-level entries ------------------------------------------------------------
translate_to_eval <- function(
  run_id,
  created = eval_log_timestamp(),
  task,
  task_id,
  task_version = 0,
  task_file = "",
  task_attribs = c(),
  task_args = c(),
  dataset,
  model,
  model_args = c(),
  config = c(),
  # TODO: look into what this actually does
  revision = list(
    type = "git",
    origin = "https://github.com/UKGovernmentBEIS/inspect_ai.git",
    commit = "9140d8a2"
  ),
  packages = list(inspect_ai = "0.3.63"),
  scorers
) {
  list(
    run_id = run_id,
    created = created,
    task = task,
    task_id = task_id,
    task_version = task_version,
    task_file = task_file,
    task_attribs = task_attribs,
    task_args = task_args,
    dataset = dataset,
    model = model,
    model_args = model_args,
    config = config,
    revision = revision,
    packages = packages,
    scorers = scorers
  )
}

translate_to_plan <- function(
  name = "plan",
  steps = translate_to_plan_steps(),
  config = c()
) {
  list(
    name = name,
    steps = steps,
    config = config
  )
}

translate_to_results <- function(
  total_samples,
  completed_samples,
  scores
) {
  list(
    total_samples = total_samples,
    completed_samples = completed_samples,
    scores = scores
  )
}

translate_to_plan_steps <- function(name, arguments, system_prompt = NULL) {
  steps <- list()

  if (!is.null(system_prompt)) {
    steps <- append(
      steps,
      list(list(
        solver = "system_message",
        params = list(template = system_prompt)
      ))
    )
  }

  steps <- append(
    steps,
    list(list(
      solver = name,
      params = arguments
    ))
  )

  steps
}

translate_to_stats <- function(
  started_at,
  completed_at,
  model_usage
) {
  list(
    started_at = started_at,
    completed_at = completed_at,
    model_usage = model_usage
  )
}

translate_to_samples <- function(dataset, scores, timestamps) {
  res <- list()
  for (i in seq_len(nrow(dataset))) {
    sample <- dataset[i, , drop = FALSE]
    res[[i]] <- translate_to_sample(
      sample,
      scores = scores,
      timestamps = timestamps
    )
  }
  res
}

translate_to_sample <- function(sample, scores, timestamps) {
  chat <- sample$solver_chat[[1]]
  scorer_name <- scores$name
  if ("scorer_chat" %in% names(sample)) {
    scorer_name <- paste0(
      c(
        scorer_name,
        " (",
        sample$scorer_chat[[1]]$get_model(),
        ")"
      ),
      collapse = ""
    )
  }
  turns <- chat$get_turns()
  list(
    id = sample$id,
    epoch = if ("epoch" %in% colnames(sample)) {
      sample$epoch
    } else {
      1
    },
    input = input_string(sample$input[[1]]),
    target = as.character(sample$target),
    messages = translate_to_messages(chat),
    output = translate_to_output(chat),
    scores = dots_list(
      !!scorer_name := translate_to_score(
        output = sample$result[[1]],
        score = sample$score[[1]],
        scorer = scorer_name,
        scorer_chat = if ("scorer_chat" %in% names(sample)) {
          sample$scorer_chat[[1]]
        } else {
          NULL
        },
        metadata = as_metadata(sample[names(sample) == "scorer_metadata"])
      )
    ),
    metadata = as_metadata(sample[names(sample) == "solver_metadata"]),
    store = c(),
    events = translate_to_events(sample = sample, timestamps = timestamps),
    model_usage = sum_model_usage(list(chat)),
    # TODO: these seem to be prompts passed to the judges
    attachments = c()
  )
}

# sub-level entries ------------------------------------------------------------
translate_to_metrics <- function(
  name = character(),
  value = numeric(),
  options = list()
) {
  list(
    name = name,
    value = value,
    options = options
  )
}

translate_to_score <- function(
  output,
  score,
  scorer,
  scorer_chat = NULL,
  metadata
) {
  if (is.null(scorer_chat)) {
    return(list(
      value = score,
      answer = as.character(output),
      explanation = scorer,
      metadata = metadata
    ))
  }

  turns <- scorer_chat$get_turns()
  explanation <- scorer_chat$last_turn()@text

  list(
    value = score,
    answer = as.character(output),
    explanation = explanation,
    metadata = c(
      list(
        grading = lapply(turns, translate_to_metadata_grading)
      ),
      metadata
    )
  )
}

# Inspect formats the content a bit differently depending
# on whether the turn role is user vs. assistant.
translate_to_metadata_grading <- function(turn) {
  if (turn@role == "user") {
    return(
      list(
        id = generate_id(),
        content = turn@text,
        role = "user"
      )
    )
  }

  list(
    id = generate_id(),
    content = list(list(type = "text", text = turn@text)),
    source = "generate",
    role = turn@role
  )
}

translate_to_eval_scorers <- function(name) {
  list(list(
    name = name,
    options = c(),
    # TODO: make this dynamic once implemented
    metrics = list(
      list(name = "mean", options = c())
    ),
    metadata = c()
  ))
}

# format single-row tibble as a string with column names as prefixes
# followed by a colon, with entries separated by newlines.
input_string <- function(x) {
  if (is.character(x)) {
    return(x)
  }
  paste0(
    mapply(
      function(name, value) paste0(name, ": ", value),
      names(x),
      as.list(x[1, ])
    ),
    collapse = "\n\n"
  )
}

# metadata entries must ultimately be a "flattened", named list.
# note `c()` is interpreted as a named list by jsonlite.
# we're not interested in recursing here; provide a lossy summary of the object
as_metadata <- function(x) {
  result <- if (is.list(x) && !has_class(x)) {
    x
  } else if (is.data.frame(x) || (is.atomic(x) && !is.null(names(x)))) {
    as.list(x)
  } else {
    list(capture.output(print(x)))
  }

  result <- set_reasonable_names(result)

  lapply(result, function(el) {
    if (!is.list(el)) {
      el
    } else if (length(el) == 1 && has_class(el[[1]])) {
      capture.output(print(el[[1]]))
    } else {
      capture.output(if (has_class(el)) print(el) else str(el))
    }
  })
}

has_class <- function(x) {
  !is.null(class(x)) && !identical(class(x), "list")
}

set_reasonable_names <- function(x) {
  if (is.null(names(x))) {
    names(x) <- as.character(seq_along(x))
    return(x)
  }

  unnamed_idx <- which(names(x) == "")
  names(x)[unnamed_idx] <- as.character(unnamed_idx)
  x
}
