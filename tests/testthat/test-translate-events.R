test_that("translate_turns works", {
  skip_on_cran()
  example_sample <- example_task()$get_samples()[1, , drop = FALSE]
  timestamps <- list(started_at = Sys.time(), completed_at = Sys.time())
  chat_translated <- translate_to_events(
    example_sample,
    timestamps = list(solve = timestamps, score = timestamps)
  )

  inspect_log <- example_inspect_log()
  inspect_log_first_events <- inspect_log$samples[[1]]$events

  expect_contains(
    names(inspect_log_first_events[[1]]),
    names(chat_translated[[1]])
  )

  expect_contains(
    names(inspect_log_first_events[[2]]),
    names(chat_translated[[2]])
  )
})

test_that("vitals writes valid eval logs (scorer tool calls, claude)", {
  vcr::local_cassette("translate-anthropic-scorer-tool-calls")
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)
  library(ellmer)

  sum_problems <- tibble::tibble(
    input = c(
      "What is 125 + 267?",
      "What is 543 + 789?",
      "What is 91 + 38?"
    ),
    target = c("392", "1332", "129")
  )

  take_sum <- tool(
    function(a, b) {
      list(sum = a + b)
    },
    name = "sum_tool",
    description = "Add two numbers together to verify arithmetic. Always use this tool.",
    arguments = list(
      a = type_number("First number"),
      b = type_number("Second number")
    )
  )

  scorer_chat <- chat_claude(
    model = "claude-sonnet-4-5-20250929",
    system_prompt = paste(
      "You are a scorer that checks arithmetic answers.",
      "ALWAYS use the sum_tool to verify the answer before grading.",
      "Call sum_tool with the numbers from the question, then compare",
      "the result to the submitted answer."
    )
  )
  scorer_chat$register_tool(take_sum)

  tsk <- Task$new(
    dataset = sum_problems,
    solver = generate(chat_claude(model = "claude-sonnet-4-5-20250929")),
    scorer = model_graded_qa(scorer_chat = scorer_chat)
  )
  tsk$eval()
  expect_valid_log(tsk$log())
})
