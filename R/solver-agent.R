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
#' proxies its model calls. The agent's transcript is then read back into
#' ellmer Chat objects so that scoring and logging work exactly as they do
#' for any other solver.
#'
#' @section Requirements:
#' These solvers require the reticulate package and a running Docker daemon
#' ([Docker Desktop](https://www.docker.com/products/docker-desktop/) or
#' similar). Python dependencies are resolved automatically with
#' [reticulate::py_require()]. The first evaluation additionally pulls the
#' sandbox image and downloads the agent's command line interface into it, so
#' it takes a few minutes longer than the ones that follow.
#'
#' @section The agent's workspace:
#' Each sample gets its own container, discarded when the sample completes,
#' so the agent's edits never touch your machine and never leak from one
#' sample to the next. The agent starts in its image's working directory,
#' falling back to the sandbox user's home directory when the image sets
#' none; pass `cwd` to place it somewhere else.
#'
#' By default that image is Inspect's own, which contains little more than a
#' Python installation. To give the agent a repository to work in, or any
#' other starting state, put a `Dockerfile` or `compose.yaml` in your working
#' directory and Inspect will build the sandbox from it, or point `sandbox`
#' at one directly:
#'
#' ```r
#' claude_code(
#'   model = "anthropic/claude-sonnet-4-5",
#'   sandbox = c("docker", "path/to/compose.yaml")
#' )
#' ```
#'
#' See Inspect's
#' [sandboxing documentation](https://inspect.aisi.org.uk/sandboxing.html)
#' for the configuration these files support.
#'
#' @param model A string identifying the model that will power the agent,
#' in Python Inspect's `"provider/model"` format, e.g.
#' `"anthropic/claude-sonnet-4-5"`. The provider must be supported by both
#' Inspect (which serves the model) and ellmer (which reconstructs the
#' agent's transcript). The agent reaches the model through Inspect rather
#' than directly, so it needs no credentials of its own: set your API key on
#' the host as usual and any provider Inspect can serve will work, whatever
#' agent it powers. Python SDKs for common providers are resolved
#' automatically; for less common ones, you may need to make the provider's
#' SDK available yourself with [reticulate::py_require()].
#' @param ... Additional named arguments, routed by name to either the
#' inspect_swe agent—e.g. `system_prompt`, `disallowed_tools`, `cwd`, or
#' `env`, documented in
#' [inspect_swe's reference](https://meridianlabs-ai.github.io/inspect_swe/reference/)—or
#' to Python Inspect's `eval()`, e.g. `max_samples`, `max_sandboxes`,
#' `time_limit`, or `token_limit`. (`epochs` is the exception: pass it to
#' [Task]'s `$eval()` method as usual.)
#' @param version A string specifying the agent CLI version to use.
#' `"auto"` (the default) uses a version already installed in the sandbox,
#' falling back to the current stable (Claude Code) or latest (Codex)
#' release. Pass a specific version (e.g. `"2.1.37"`) for reproducibility.
#' @param sandbox The Inspect sandbox in which the agent runs: a string
#' naming the sandbox type, or a length-2 vector pairing a type with a
#' configuration file, e.g. `c("docker", "compose.yaml")`. Defaults to
#' `"docker"`, which is required on macOS and Windows; on Linux hosts,
#' `"local"` runs the agent directly on the host.
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
claude_code <- function(model, ..., version = "auto", sandbox = "docker") {
  agent_solver(
    agent = "claude_code",
    bridge_package = "anthropic",
    model = model,
    args = list2(...),
    version = version,
    sandbox = sandbox
  )
}

#' @rdname agent_solvers
#' @export
codex <- function(model, ..., version = "auto", sandbox = "docker") {
  agent_solver(
    agent = "codex_cli",
    bridge_package = "openai",
    model = model,
    args = list2(...),
    version = version,
    sandbox = sandbox
  )
}

agent_solver <- function(
  agent,
  bridge_package,
  model,
  args,
  version,
  sandbox,
  call = rlang::caller_env()
) {
  check_string(model, call = call)
  check_string(version, call = call)
  check_sandbox(sandbox, call = call)
  check_agent_dots(args, call = call)

  args$version <- version

  function(inputs, ...) {
    solve_with_inspect_agent(
      inputs = inputs,
      agent = agent,
      bridge_package = bridge_package,
      args = args,
      model = model,
      sandbox = sandbox
    )
  }
}

solve_with_inspect_agent <- function(
  inputs,
  agent,
  bridge_package,
  args,
  model,
  sandbox,
  call = rlang::caller_env()
) {
  check_inspect_agent_deps(sandbox, call = call)
  check_agent_model(model, call = call)
  # Inspect's bridge talks to the agent in the agent's own API dialect, so it
  # needs that SDK whatever provider ends up serving the model
  reticulate::py_require(unique(c(
    "inspect-ai",
    "inspect-swe",
    bridge_package,
    inspect_provider_packages(model)
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
  agent_fn <- reticulate::py_get_attr(imports$inspect_swe, agent)

  args <- split_agent_args(
    coerce_whole_numbers(args),
    agent_params = py_argument_names(agent_fn),
    eval_params = c(py_argument_names(inspect$eval), py_generate_config_names()),
    call = call
  )

  inputs <- purrr::map_chr(as.list(inputs), input_string)
  samples <- purrr::imap(
    unname(as.list(inputs)),
    function(input, i) inspect_dataset$Sample(input = input, id = i)
  )

  task <- inspect$Task(
    dataset = inspect_dataset$MemoryDataset(samples),
    solver = do.call(agent_fn, args$agent),
    sandbox = inspect_sandbox(sandbox),
    name = agent
  )

  log_dir <- file.path(tempdir(), "inspect-logs", generate_id())
  dir.create(log_dir, recursive = TRUE, showWarnings = FALSE)

  eval_args <- args$eval
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

  result <- nonempty(sample$output$completion) %||%
    nonempty(error) %||%
    nonempty(response_text(chat)) %||%
    "The agent returned no response."

  list(
    result = result,
    solver_chat = with_response(chat, result),
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

response_text <- function(chat) {
  turns <- chat$get_turns()
  last_turn <- if (length(turns) > 0) turns[[length(turns)]]
  if (!is.null(last_turn) && identical(last_turn@role, "assistant")) {
    last_turn@text
  }
}

# an agent that errors partway can leave a transcript with no response in it,
# which both scoring and log translation assume is there
with_response <- function(chat, text) {
  if (!is.null(response_text(chat))) {
    return(chat)
  }
  chat$set_turns(c(
    chat$get_turns(),
    list(ellmer::AssistantTurn(contents = list(ellmer::ContentText(text))))
  ))
  chat
}

nonempty <- function(x) {
  if (is.null(x) || identical(x, "")) NULL else x
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

check_sandbox <- function(sandbox, call = rlang::caller_env()) {
  if (
    !is.character(sandbox) ||
      !length(sandbox) %in% c(1L, 2L) ||
      anyNA(sandbox)
  ) {
    cli::cli_abort(
      "{.arg sandbox} must be a sandbox type or a pair of sandbox type and
       configuration file, e.g. {.code c(\"docker\", \"compose.yaml\")}.",
      call = call
    )
  }

  invisible()
}

check_agent_dots <- function(args, call = rlang::caller_env()) {
  if (length(args) > 0 && !is_named(args)) {
    cli::cli_abort(
      "All arguments in {.arg ...} must be named.",
      call = call
    )
  }

  if ("epochs" %in% names(args)) {
    cli::cli_abort(
      c(
        "{.arg epochs} can't be set on an agent solver.",
        i = "Pass it to {.help [Task](vitals::Task)}'s {.fun $eval} method
             instead."
      ),
      call = call
    )
  }

  reserved <- intersect(names(args), c("solver", "log_dir", "log_format"))
  if (length(reserved) > 0) {
    cli::cli_abort(
      "{.arg {reserved}} {?is/are} determined by the solver and can't
       be set.",
      call = call
    )
  }

  invisible()
}

split_agent_args <- function(args, agent_params, eval_params, call) {
  is_agent <- names(args) %in% agent_params
  is_eval <- !is_agent & names(args) %in% eval_params

  unknown <- names(args)[!is_agent & !is_eval]
  if (length(unknown) > 0) {
    cli::cli_abort(
      c(
        "{.arg {unknown}} {?is/are} not {?an argument/arguments} of the agent
         or of Python Inspect's {.fun eval}.",
        i = "See {.url https://meridianlabs-ai.github.io/inspect_swe/reference/}
             for the agent's arguments."
      ),
      call = call
    )
  }

  list(agent = args[is_agent], eval = args[is_eval])
}

py_argument_names <- function(fn) {
  py_inspect <- reticulate::import("inspect")
  params <- py_inspect$signature(fn)$parameters
  names <- reticulate::import_builtins()$list(params)
  kinds <- purrr::map_int(names, function(name) {
    as.integer(params[[name]]$kind)
  })
  variadic <- c(
    py_inspect$Parameter$VAR_POSITIONAL,
    py_inspect$Parameter$VAR_KEYWORD
  )
  names[!kinds %in% as.integer(variadic)]
}

# `eval()` takes generation options like `max_tokens` as **kwargs, so they
# don't show up in its signature
py_generate_config_names <- function() {
  config <- reticulate::import("inspect_ai.model")$GenerateConfig
  reticulate::import_builtins()$list(config$model_fields)
}

inspect_sandbox <- function(sandbox) {
  if (length(sandbox) == 1) {
    return(sandbox)
  }
  reticulate::tuple(sandbox[[1]], sandbox[[2]])
}

# inspect-ai keeps provider SDKs as optional dependencies and raises a
# `pip install <sdk>` error on first use, which isn't actionable when
# reticulate is resolving the environment
inspect_provider_packages <- function(model) {
  provider <- sub("/.*", "", model)
  switch(
    provider,
    anthropic = "anthropic",
    openai = ,
    `openai-api` = ,
    together = ,
    perplexity = ,
    openrouter = ,
    ollama = "openai",
    google = "google-genai",
    mistral = "mistralai",
    groq = "groq",
    character(0)
  )
}

# reticulate maps R doubles to Python floats, which fall through
# `isinstance(x, int)` dispatch (e.g. inspect_swe's `attempts`) and fail
# mid-eval rather than when the solver is constructed
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
