test_that("vitals works with live OpenAI models", {
  skip_on_cran()
  key_get("OPENAI_API_KEY")
  withr::local_envvar(list(VITALS_LOG_DIR = withr::local_tempdir()))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  tsk <- Task$new(
    dataset = tibble::tibble(input = "What's 2+2?", target = "4"),
    solver = generate(ellmer::chat_openai(model = "gpt-5.4-nano")),
    scorer = model_graded_qa()
  )
  tsk$eval()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_gt(sum(tsk$get_cost()$input), 0)
  expect_valid_log(tsk$log())
})

test_that("vitals works with live Anthropic models and tools", {
  skip_on_cran()
  key_get("ANTHROPIC_API_KEY")
  withr::local_envvar(list(VITALS_LOG_DIR = withr::local_tempdir()))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  ch <- ellmer::chat_anthropic(model = "claude-sonnet-5-5")
  ch$register_tool(ellmer::tool(
    function() "2024-01-01",
    name = "get_current_date",
    description = "Return the current date"
  ))

  tsk <- Task$new(
    dataset = tibble::tibble(
      input = "Use the tool to find the current date.",
      target = "2024-01-01"
    ),
    solver = generate(ch),
    scorer = model_graded_qa()
  )
  tsk$eval()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_gt(sum(tsk$get_cost()$input), 0)
  expect_valid_log(tsk$log())
})

test_that("vitals works with live Gemini models", {
  skip_on_cran()
  key_get("GOOGLE_API_KEY")
  withr::local_envvar(list(VITALS_LOG_DIR = withr::local_tempdir()))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  tsk <- Task$new(
    dataset = tibble::tibble(input = "What's 2+2?", target = "4"),
    solver = generate(ellmer::chat_google_gemini(model = "gemini-3.8-flash")),
    scorer = model_graded_qa()
  )
  tsk$eval()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_gt(sum(tsk$get_cost()$input), 0)
  expect_valid_log(tsk$log())
})
