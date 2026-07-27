test_that("claude_code checks inputs", {
  expect_snapshot(error = TRUE, claude_code(mock_chat_template(), "boop"))
  expect_snapshot(
    error = TRUE,
    claude_code(mock_chat_template(), sandbox = c("docker", 1, 2))
  )
  expect_snapshot(error = TRUE, claude_code(version = 1))
})

test_that("agent solvers check their chat when they solve", {
  solver <- claude_code("not a chat")
  expect_snapshot(error = TRUE, solver("What's 2+2?"))

  chat <- mock_chat_template()
  chat$set_tools(list(ellmer::tool(function() "boop", name = "boop", description = "Boop.")))
  solver <- codex(chat)
  expect_snapshot(error = TRUE, solver("What's 2+2?"))
})

test_that("claude_code returns a solver function", {
  solver <- claude_code(mock_chat_template())
  expect_true(is.function(solver))
  expect_equal(names(formals(solver)), c("inputs", "...", "solver_chat"))
})

test_that("import_inspect_log reconstructs solved samples", {
  res <- import_inspect_log(
    example_claude_code_log(),
    inputs = "What is the capital of France? Reply with just the city name.",
    chat = mock_chat_template()
  )

  expect_named(res, c("result", "solver_chat", "solver_metadata"))
  expect_equal(res$result, "Paris")

  chat <- res$solver_chat[[1]]
  expect_s3_class(chat, "Chat")
  expect_equal(chat$get_model(), "claude-haiku-4-5-20251001")
  expect_gte(length(chat$get_turns()), 2)
  expect_equal(chat$last_turn()@text, "Paris")

  tokens <- chat$get_tokens()
  expect_gt(sum(tokens$input, tokens$output), 0)

  metadata <- res$solver_metadata[[1]]
  expect_equal(metadata$inspect_log, example_claude_code_log())
  expect_named(metadata$model_usage, "anthropic/claude-haiku-4-5-20251001")
  expect_null(metadata$error)
})

test_that("import_inspect_log errors informatively on failed evals", {
  log <- jsonlite::read_json(example_claude_code_log())
  log$status <- "error"
  log$error <- list(message = "sandbox exploded")
  path <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(log, path, auto_unbox = TRUE)

  expect_snapshot(
    error = TRUE,
    import_inspect_log(
      path,
      inputs = "What is the capital of France? Reply with just the city name.",
      chat = mock_chat_template()
    ),
    transform = function(lines) gsub(path, "<log_path>", lines, fixed = TRUE)
  )
})

test_that("import_inspect_log errors informatively on sample count mismatch", {
  path <- example_claude_code_log()
  expect_snapshot(
    error = TRUE,
    import_inspect_log(path, inputs = c("one", "two"), chat = mock_chat_template()),
    transform = function(lines) gsub(path, "<log_path>", lines, fixed = TRUE)
  )
})

test_that("import_inspect_sample recovers from errored samples", {
  sample <- list(
    id = 1L,
    messages = list(),
    output = NULL,
    error = list(message = "agent crashed"),
    model_usage = NULL
  )

  res <- import_inspect_sample(
    sample,
    input = "hey there",
    model = "anthropic/claude-haiku-4-5-20251001",
    chat = mock_chat_template(),
    call = rlang::current_env()
  )

  expect_equal(res$result, "agent crashed")
  expect_s3_class(res$solver_chat, "Chat")
  turns <- res$solver_chat$get_turns()
  expect_length(turns, 2)
  expect_equal(turns[[1]]@text, "hey there")
  expect_equal(turns[[2]]@text, "agent crashed")
  expect_equal(res$metadata$error, "agent crashed")
})

test_that("import_inspect_sample gives partial transcripts a response", {
  sample <- list(
    id = 1L,
    messages = list(list(role = "user", content = "hey there")),
    output = NULL,
    error = list(message = "agent crashed"),
    model_usage = NULL
  )

  res <- import_inspect_sample(
    sample,
    input = "hey there",
    model = "anthropic/claude-haiku-4-5-20251001",
    chat = mock_chat_template(),
    call = rlang::current_env()
  )

  expect_equal(res$result, "agent crashed")
  turns <- res$solver_chat$get_turns()
  expect_equal(
    purrr::map_chr(turns, function(turn) turn@role),
    c("user", "assistant")
  )
  expect_equal(turns[[2]]@text, "agent crashed")

  sample$error <- NULL
  res <- import_inspect_sample(
    sample,
    input = "hey there",
    model = "anthropic/claude-haiku-4-5-20251001",
    chat = mock_chat_template(),
    call = rlang::current_env()
  )

  expect_equal(res$result, "The agent returned no response.")
  expect_equal(res$solver_chat$last_turn()@text, "The agent returned no response.")
})

test_that("inspect_provider_packages maps providers to python packages", {
  expect_equal(inspect_provider_packages("anthropic/some-model"), "anthropic")
  expect_equal(inspect_provider_packages("openai/some-model"), "openai")
  expect_equal(inspect_provider_packages("google/some-model"), "google-genai")
  expect_equal(inspect_provider_packages("mistral/some-model"), "mistralai")
  expect_equal(inspect_provider_packages("groq/some-model"), "groq")
  expect_equal(inspect_provider_packages("bedrock/some-model"), character(0))
  expect_equal(inspect_provider_packages("hf/some-model"), character(0))
})

test_that("coerce_whole_numbers converts only whole doubles", {
  expect_identical(
    coerce_whole_numbers(list(a = 600, b = 0.5, c = TRUE, d = "x", e = 2L)),
    list(a = 600L, b = 0.5, c = TRUE, d = "x", e = 2L)
  )
})

test_that("claude_code end to end", {
  skip_if(Sys.getenv("VITALS_TEST_AGENT_SOLVERS") == "")
  skip_if_not_installed("reticulate")
  skip_if(Sys.which("docker") == "")
  skip_if(Sys.getenv("ANTHROPIC_API_KEY") == "")

  tsk <- Task$new(
    dataset = tibble::tibble(
      input = "What is the capital of France? Reply with just the city name.",
      target = "Paris"
    ),
    solver = claude_code(
      ellmer::chat_anthropic(model = "claude-haiku-4-5-20251001")
    ),
    scorer = detect_includes(),
    dir = withr::local_tempdir()
  )

  tsk$eval(view = FALSE)

  samples <- tsk$get_samples()
  expect_equal(samples$score, factor("C", levels = c("I", "C")))
  expect_valid_log(tsk$log())
})

test_that("agent solvers reject reserved arguments", {
  expect_snapshot(
    error = TRUE,
    claude_code(mock_chat_template(), epochs = 2)
  )
  expect_snapshot(
    error = TRUE,
    codex(mock_chat_template(), log_dir = "logs")
  )
})

test_that("split_agent_args routes arguments by signature", {
  args <- split_agent_args(
    list(system_prompt = "be brief", max_samples = 2L),
    agent_params = c("system_prompt", "version"),
    eval_params = c("max_samples", "model"),
    call = rlang::current_env()
  )

  expect_equal(args$agent, list(system_prompt = "be brief"))
  expect_equal(args$eval, list(max_samples = 2L))

  expect_snapshot(
    error = TRUE,
    split_agent_args(
      list(not_an_argument = 1),
      agent_params = "system_prompt",
      eval_params = "max_samples",
      call = rlang::current_env()
    )
  )
})

test_that("coerce_whole_numbers leaves doubles beyond integer range alone", {
  expect_identical(coerce_whole_numbers(list(a = 1e10))$a, 1e10)
})

test_that("with_chat_args forwards the chat's prompt and params", {
  chat <- mock_chat_template(
    system_prompt = "Be terse.",
    params = ellmer::params(temperature = 0, stop_sequences = "STOP")
  )

  args <- with_chat_args(
    list(agent = list(), eval = list()),
    chat,
    config_names = c("temperature", "stop_seqs")
  )

  expect_equal(args$agent$system_prompt, "Be terse.")
  expect_equal(args$eval, list(temperature = 0, stop_seqs = "STOP"))

  # arguments passed to the solver directly win
  args <- with_chat_args(
    list(agent = list(system_prompt = "Be brief."), eval = list(temperature = 1)),
    chat,
    config_names = c("temperature", "stop_seqs")
  )

  expect_equal(args$agent$system_prompt, "Be brief.")
  expect_equal(args$eval$temperature, 1)
})

test_that("with_chat_args errors on params Inspect can't pass along", {
  chat <- mock_chat_template(params = ellmer::params(made_up = 1))
  expect_snapshot(
    error = TRUE,
    with_chat_args(
      list(agent = list(), eval = list()),
      chat,
      config_names = "temperature"
    )
  )
})

test_that("inspect_model_string maps ellmer providers", {
  expect_equal(
    inspect_model_string(mock_chat_template(model = "some-model")),
    "openai_compatible/some-model"
  )
})

test_that("ellmer_model_string maps Inspect provider prefixes", {
  expect_equal(
    ellmer_model_string("google/gemini-2.5-pro"),
    "google_gemini/gemini-2.5-pro"
  )
  expect_equal(
    ellmer_model_string("anthropic/some-model"),
    "anthropic/some-model"
  )
  expect_equal(ellmer_model_string("some-model"), "some-model")
})
