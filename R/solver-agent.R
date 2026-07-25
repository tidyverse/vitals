#' Coding agents as solvers
#'
#' @description
#' `claude_code()` and `codex()` are solvers that evaluate the Claude Code
#' and Codex coding agents on your dataset, allowing you to compare
#' off-the-shelf agent harnesses against your own with the same scorer.
#'
#' These solvers bridge to Python Inspect's
#' [inspect_swe](https://meridianlabs-ai.github.io/inspect_swe/) package,
#' which runs the agent's command line interface in a Docker sandbox and
#' proxies its model calls: the sandbox never sees your API key, and every
#' model call the agent makes is recorded in the resulting transcript. The
#' agent's transcript is then read back into ellmer Chat objects so that
#' scoring and logging work exactly as they do for any other solver.
#'
#' @section Requirements:
#' These solvers require the reticulate package and a running Docker daemon
#' ([Docker Desktop](https://www.docker.com/products/docker-desktop/) or
#' similar); the first evaluation will pull Inspect's default sandbox image.
#' Python dependencies are resolved automatically with
#' [reticulate::py_require()]. Set your API key (e.g. `ANTHROPIC_API_KEY`)
#' as usual—it's read on the host by Inspect and never enters the sandbox.
#'
#' @param model A string identifying the model that will power the agent,
#' in Python Inspect's `"provider/model"` format, e.g.
#' `"anthropic/claude-sonnet-4-5"`. The provider must be supported by both
#' Inspect (which serves the model) and ellmer (which reconstructs the
#' agent's transcript). Python SDKs for common providers are resolved
#' automatically; for less common ones, you may need to make the provider's
#' SDK available yourself with [reticulate::py_require()].
#' @param system_prompt Optional. A string containing additional system
#' prompt content to append to the agent's default system prompt.
#' @param disallowed_tools Optional. A character vector of agent tool names
#' to disallow (Claude Code only).
#' @param version A string specifying the agent CLI version to use.
#' `"auto"` (the default) uses a version already installed in the sandbox,
#' falling back to the current stable (Claude Code) or latest (Codex)
#' release. Pass a specific version (e.g. `"2.1.37"`) for reproducibility.
#' @param sandbox A string specifying the Inspect sandbox type in which the
#' agent runs. Defaults to `"docker"`, which is required on macOS and
#' Windows; on Linux hosts, `"local"` runs the agent directly on the host.
#' @param agent_args Optional. A named list of additional arguments passed
#' to the underlying inspect_swe agent (e.g. `cwd`, `env`).
#' @param ... Additional arguments passed to Python Inspect's `eval()`,
#' e.g. `max_samples`, `max_sandboxes`, `time_limit`, or `token_limit`.
#' (`epochs` is the exception: pass it to [Task]'s `$eval()` method as
#' usual.)
#'
#' @returns
#' A solver function that can be passed directly to the `solver` argument of
#' [Task]'s `$new()` method. Since the agent runs in a sandbox rather than
#' through an ellmer Chat, the solver's `solver_chat` output contains Chat
#' objects reconstructed from the agent's transcript. Each sample's
#' `solver_metadata` records the path to the intermediate Inspect log,
#' the sample's token usage by model, and the agent's error message (if any).
#'
#' Token usage is recorded in the task's log and in `solver_metadata`, but
#' not in [Task]'s `$token_usage()` method, which only reflects API calls
#' made through ellmer in the current R session.
#'
#' @examples
#' if (FALSE) {
#'   library(tibble)
#'
#'   simple_addition <- tibble(
#'     input = c("What's 2+2?", "What's 2+3?"),
#'     target = c("4", "5")
#'   )
#'
#'   tsk <- Task$new(
#'     dataset = simple_addition,
#'     solver = claude_code(model = "anthropic/claude-sonnet-4-5"),
#'     scorer = detect_includes()
#'   )
#'
#'   tsk$eval()
#' }
#'
#' @name agent_solvers
#' @export
claude_code <- function(
  model,
  system_prompt = NULL,
  disallowed_tools = NULL,
  version = "auto",
  sandbox = "docker",
  agent_args = list(),
  ...
) {
  check_string(model)
  check_string(system_prompt, allow_null = TRUE)
  check_character(disallowed_tools, allow_null = TRUE)
  check_string(version)
  check_string(sandbox)
  check_agent_args(
    agent_args,
    reserved = c("system_prompt", "disallowed_tools", "version")
  )
  eval_args <- check_eval_args(list2(...))

  agent_args <- c(
    purrr::compact(list(
      system_prompt = system_prompt,
      disallowed_tools = as.list(disallowed_tools),
      version = version
    )),
    agent_args
  )

  function(inputs, ...) {
    solve_with_inspect_agent(
      inputs = inputs,
      agent = "claude_code",
      agent_args = agent_args,
      model = model,
      sandbox = sandbox,
      eval_args = eval_args
    )
  }
}

#' @rdname agent_solvers
#' @export
codex <- function(
  model,
  system_prompt = NULL,
  version = "auto",
  sandbox = "docker",
  agent_args = list(),
  ...
) {
  check_string(model)
  check_string(system_prompt, allow_null = TRUE)
  check_string(version)
  check_string(sandbox)
  check_agent_args(agent_args, reserved = c("system_prompt", "version"))
  eval_args <- check_eval_args(list2(...))

  agent_args <- c(
    purrr::compact(list(
      system_prompt = system_prompt,
      version = version
    )),
    agent_args
  )

  function(inputs, ...) {
    solve_with_inspect_agent(
      inputs = inputs,
      agent = "codex_cli",
      agent_args = agent_args,
      model = model,
      sandbox = sandbox,
      eval_args = eval_args,
      packages = "openai"
    )
  }
}

solve_with_inspect_agent <- function(
  inputs,
  agent,
  agent_args,
  model,
  sandbox,
  eval_args,
  packages = character(),
  call = rlang::caller_env()
) {
  check_inspect_agent_deps(sandbox, call = call)
  check_agent_model(model, call = call)
  reticulate::py_require(unique(c(
    "inspect-ai",
    "inspect-swe",
    inspect_provider_packages(model),
    packages
  )))

  imports <- tryCatch(
    list(
      inspect = reticulate::import("inspect_ai"),
      inspect_dataset = reticulate::import("inspect_ai.dataset"),
      inspect_swe = reticulate::import("inspect_swe")
    ),
    error = function(cnd) {
      cli::cli_abort(
        c(
          "Unable to import the {.pkg inspect_ai} and {.pkg inspect_swe}
           Python packages.",
          i = "If reticulate is configured to use an existing Python
               environment (e.g. via {.envvar RETICULATE_PYTHON}), install
               them there; otherwise vitals installs them automatically via
               {.fun reticulate::py_require}."
        ),
        parent = cnd,
        call = call
      )
    }
  )
  inspect <- imports$inspect
  inspect_dataset <- imports$inspect_dataset
  inspect_swe <- imports$inspect_swe

  agent_args <- coerce_whole_numbers(agent_args)

  inputs <- purrr::map_chr(as.list(inputs), input_string)
  samples <- purrr::imap(
    unname(as.list(inputs)),
    function(input, i) inspect_dataset$Sample(input = input, id = i)
  )

  task <- inspect$Task(
    dataset = inspect_dataset$MemoryDataset(samples),
    solver = do.call(reticulate::py_get_attr(inspect_swe, agent), agent_args),
    sandbox = sandbox,
    name = agent
  )

  log_dir <- file.path(tempdir(), "inspect-logs", generate_id())
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  eval_args <- coerce_whole_numbers(eval_args)
  eval_args$display <- eval_args$display %||% "plain"
  eval_args$fail_on_error <- eval_args$fail_on_error %||% FALSE
  eval_args$log_dir <- log_dir
  eval_args$log_format <- "json"

  do.call(inspect$eval, c(list(task, model = model), eval_args))

  log_path <- list.files(log_dir, pattern = "\\.json$", full.names = TRUE)
  if (length(log_path) != 1) {
    cli::cli_abort(
      "Expected one Inspect log in {.file {log_dir}}, found {length(log_path)}.",
      call = call
    )
  }

  import_inspect_log(log_path, inputs = inputs, call = call)
}

import_inspect_log <- function(log_path, inputs, call = rlang::caller_env()) {
  log <- eval_log_read(log_path)
  if (!identical(log$status, "success")) {
    cli::cli_abort(
      c(
        "The Inspect eval powering this solver did not complete successfully
         (status {.val {log$status}}).",
        i = log$error$message %||% character(),
        i = "{length(log$samples)} sample transcript{?s} completed before
             the failure and remain{?s/} in the log.",
        i = "See {.file {log_path}} for the full log."
      ),
      call = call
    )
  }

  samples <- log$samples[order(purrr::map_int(
    log$samples,
    function(sample) as.integer(sample$id)
  ))]

  if (length(samples) != length(inputs)) {
    cli::cli_abort(
      c(
        "The Inspect log contains {length(samples)} sample{?s} but
         {length(inputs)} input{?s} were provided.",
        i = "See {.file {log_path}} for the full log."
      ),
      call = call
    )
  }

  imported <- purrr::map2(
    samples,
    inputs,
    import_inspect_sample,
    model = log$eval$model,
    call = call
  )

  list(
    result = purrr::map_chr(imported, "result"),
    solver_chat = purrr::map(imported, "solver_chat"),
    solver_metadata = purrr::map(imported, function(sample) {
      c(
        list(inspect_log = log_path),
        sample$metadata
      )
    })
  )
}

import_inspect_sample <- function(sample, input, model, call) {
  attachments <- list2env(
    sample$attachments %||% list(),
    envir = new.env(parent = emptyenv())
  )
  sample <- resolve_attachments(sample, attachments)
  error <- sample$error$message

  chat <- if (length(sample$messages) > 0) {
    chat_from_log_messages(
      sample$messages,
      model = model,
      model_events = log_model_events(sample$events %||% list()),
      call = call
    )
  } else {
    errored_chat(input, error %||% "The agent returned no messages.", model)
  }

  result <- sample$output$completion
  if (is.null(result) || identical(result, "")) {
    last_turn <- chat$last_turn()
    fallback <- ""
    if (!is.null(last_turn) && identical(last_turn@role, "assistant")) {
      fallback <- last_turn@text
    }
    result <- error %||% fallback
  }

  list(
    result = result,
    solver_chat = chat,
    metadata = purrr::compact(list(
      model_usage = sample$model_usage,
      error = error
    ))
  )
}

errored_chat <- function(input, error, model) {
  chat <- chat_from_model_string(model)
  chat$set_turns(list(
    ellmer::UserTurn(contents = list(ellmer::ContentText(input))),
    ellmer::AssistantTurn(contents = list(ellmer::ContentText(error)))
  ))
  chat
}

check_inspect_agent_deps <- function(sandbox, call = rlang::caller_env()) {
  rlang::check_installed(
    "reticulate",
    version = "1.41",
    reason = "to evaluate coding agent solvers."
  )

  if (!identical(sandbox, "docker")) {
    return(invisible())
  }

  if (Sys.which("docker") == "") {
    cli::cli_abort(
      c(
        "Coding agent solvers require Docker when {.code sandbox = \"docker\"}.",
        i = "Install Docker Desktop or similar and ensure {.code docker} is
             on your {.envvar PATH}."
      ),
      call = call
    )
  }

  daemon_ok <- suppressWarnings(
    system2("docker", "info", stdout = FALSE, stderr = FALSE)
  )
  if (!identical(daemon_ok, 0L)) {
    cli::cli_abort(
      c(
        "Docker is installed but its daemon isn't running.",
        i = "Start Docker and try again."
      ),
      call = call
    )
  }

  invisible()
}

check_agent_model <- function(model, call = rlang::caller_env()) {
  tryCatch(
    ellmer::chat(ellmer_model_string(model)),
    error = function(cnd) {
      cli::cli_abort(
        c(
          "ellmer must be able to construct a Chat for {.val {model}} so
           that the agent's transcript can be read back after solving.",
          i = "Choose a model from a provider that both Inspect and ellmer
               support."
        ),
        parent = cnd,
        call = call
      )
    }
  )
  invisible()
}

check_agent_args <- function(
  agent_args,
  reserved = character(),
  call = rlang::caller_env()
) {
  if (
    !is.list(agent_args) ||
      (length(agent_args) > 0 &&
        (is.null(names(agent_args)) || any(names(agent_args) == "")))
  ) {
    cli::cli_abort(
      "{.arg agent_args} must be a named list.",
      call = call
    )
  }

  clashes <- intersect(names(agent_args), reserved)
  if (length(clashes) > 0) {
    cli::cli_abort(
      "Pass {.arg {clashes}} as {? its/their} own argument{?s} rather than
       in {.arg agent_args}.",
      call = call
    )
  }

  invisible()
}

check_eval_args <- function(eval_args, call = rlang::caller_env()) {
  if ("epochs" %in% names(eval_args)) {
    cli::cli_abort(
      c(
        "{.arg epochs} can't be set on an agent solver.",
        i = "Pass it to {.help [Task](vitals::Task)}'s {.fun $eval} method
             instead."
      ),
      call = call
    )
  }

  overwritten <- intersect(names(eval_args), c("log_dir", "log_format"))
  if (length(overwritten) > 0) {
    cli::cli_abort(
      "{.arg {overwritten}} {?is/are} determined by the solver and can't
       be set.",
      call = call
    )
  }

  eval_args
}

inspect_provider_packages <- function(model) {
  provider <- sub("/.*", "", model)
  switch(
    provider,
    anthropic = "anthropic",
    openai = ,
    `openai-api` = ,
    azureai = ,
    grok = ,
    groq = ,
    together = ,
    openrouter = ,
    ollama = "openai",
    google = ,
    vertex = "google-genai",
    mistral = "mistralai",
    bedrock = "boto3",
    character(0)
  )
}

coerce_whole_numbers <- function(args) {
  purrr::map(args, function(x) {
    if (
      is.double(x) &&
        length(x) == 1 &&
        !is.na(x) &&
        identical(x, trunc(x)) &&
        abs(x) <= .Machine$integer.max
    ) {
      as.integer(x)
    } else {
      x
    }
  })
}
