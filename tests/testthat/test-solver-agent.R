claude_code_log <- function() {
  system.file(
    "test/inspect/logs",
    "2026-07-25T12-57-47-00-00_claude-code_boWWx32BT72g5mJWxzeEDN.json",
    package = "vitals"
  )
}

claude_code_input <-
  "What is the capital of France? Reply with just the city name."

test_that("claude_code checks inputs", {
  expect_snapshot(error = TRUE, claude_code())
  expect_snapshot(error = TRUE, claude_code(model = 1))
  expect_snapshot(
    error = TRUE,
    claude_code(model = "anthropic/some-model", agent_args = list(1))
  )
})

test_that("codex checks inputs", {
  expect_snapshot(error = TRUE, codex())
  expect_snapshot(error = TRUE, codex(model = "openai/some-model", version = 1))
})

test_that("claude_code returns a solver function", {
  solver <- claude_code(model = "anthropic/some-model")
  expect_true(is.function(solver))
  expect_equal(names(formals(solver)), c("inputs", "..."))
})

test_that("import_inspect_log reconstructs solved samples", {
  res <- import_inspect_log(claude_code_log(), inputs = claude_code_input)

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
  expect_equal(metadata$inspect_log, claude_code_log())
  expect_named(metadata$model_usage, "anthropic/claude-haiku-4-5-20251001")
  expect_null(metadata$error)
})

test_that("import_inspect_log errors informatively on failed evals", {
  log <- jsonlite::read_json(claude_code_log())
  log$status <- "error"
  log$error <- list(message = "sandbox exploded")
  path <- withr::local_tempfile(fileext = ".json")
  jsonlite::write_json(log, path, auto_unbox = TRUE)

  expect_snapshot(
    error = TRUE,
    import_inspect_log(path, inputs = claude_code_input),
    transform = function(lines) gsub(path, "<log_path>", lines, fixed = TRUE)
  )
})

test_that("import_inspect_log errors informatively on sample count mismatch", {
  path <- claude_code_log()
  expect_snapshot(
    error = TRUE,
    import_inspect_log(path, inputs = c("one", "two")),
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

test_that("inspect_provider_packages maps providers to python packages", {
  expect_equal(inspect_provider_packages("anthropic/some-model"), "anthropic")
  expect_equal(inspect_provider_packages("openai/some-model"), "openai")
  expect_equal(inspect_provider_packages("google/some-model"), "google-genai")
  expect_equal(inspect_provider_packages("mistral/some-model"), "mistralai")
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
      input = claude_code_input,
      target = "Paris"
    ),
    solver = claude_code(model = "anthropic/claude-haiku-4-5-20251001"),
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
    claude_code(model = "anthropic/some-model", agent_args = list(version = "2.1.37"))
  )
  expect_snapshot(
    error = TRUE,
    claude_code(model = "anthropic/some-model", epochs = 2)
  )
  expect_snapshot(
    error = TRUE,
    codex(model = "openai/some-model", log_dir = "logs")
  )
})

test_that("coerce_whole_numbers leaves doubles beyond integer range alone", {
  expect_identical(coerce_whole_numbers(list(a = 1e10))$a, 1e10)
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
