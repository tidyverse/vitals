mock_chat_template <- function() {
  ellmer::chat_openai_compatible(
    base_url = "https://example.com",
    model = "placeholder",
    credentials = function() "fake-key"
  )
}

test_that("vitals_log_read round-trips a task log", {
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  tool_def <- ellmer::tool(
    function(a, b) a + b,
    name = "add",
    description = "Add two numbers.",
    arguments = list(
      a = ellmer::type_number("First number."),
      b = ellmer::type_number("Second number.")
    )
  )

  request <- ellmer::ContentToolRequest(
    id = "call_1",
    name = "add",
    arguments = list(a = 1, b = 2),
    tool = tool_def
  )

  chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.com",
    model = "test-model",
    system_prompt = "Be terse.",
    credentials = function() "fake-key"
  )
  chat$register_tool(tool_def)
  chat$set_turns(list(
    ellmer::UserTurn("What is 1 + 2?"),
    ellmer::AssistantTurn(
      contents = list(
        ellmer::ContentThinking(
          thinking = "I should use the tool.",
          extra = list(signature = "sig")
        ),
        ellmer::ContentText("Let me add those."),
        request
      ),
      tokens = c(10, 5, 3),
      duration = 1.5,
      finish_reason = "tool_use"
    ),
    ellmer::UserTurn(contents = list(
      ellmer::ContentToolResult(value = 3, request = request)
    )),
    ellmer::AssistantTurn(
      contents = list(ellmer::ContentText("The answer is 3.")),
      tokens = c(20, 6, 10),
      duration = 0.7,
      finish_reason = "success"
    )
  ))

  tsk <- Task$new(
    dataset = tibble::tibble(input = "What is 1 + 2?", target = "3"),
    solver = function(inputs) {
      list(result = "The answer is 3.", solver_chat = list(chat))
    },
    scorer = function(samples) {
      list(score = factor("C", levels = c("I", "C"), ordered = TRUE))
    }
  )
  tsk$eval()
  log_path <- tsk$log()

  res <- vitals_log_read(
    log_path,
    solver_chat = mock_chat_template(),
    tools = list(add = tool_def)
  )

  expect_equal(nrow(res), 1)
  expect_equal(res$input, "What is 1 + 2?")
  expect_equal(res$target, "3")
  expect_equal(res$result, "The answer is 3.")
  expect_equal(res$score, "C")
  expect_false("scorer_chat" %in% names(res))

  read_chat <- res$solver_chat[[1]]
  expect_equal(read_chat$get_model(), "test-model")
  expect_equal(read_chat$get_system_prompt(), "Be terse.")
  expect_named(read_chat$get_tools(), "add")

  turns <- read_chat$get_turns()
  expect_length(turns, 4)

  assistant <- turns[[2]]
  expect_s3_class(assistant@contents[[1]], "ellmer::ContentThinking")
  expect_equal(assistant@contents[[1]]@thinking, "I should use the tool.")
  expect_equal(assistant@contents[[1]]@extra$signature, "sig")
  expect_equal(assistant@contents[[2]]@text, "Let me add those.")
  expect_s3_class(assistant@contents[[3]], "ellmer::ContentToolRequest")
  expect_equal(assistant@contents[[3]]@arguments, list(a = 1L, b = 2L))
  expect_false(is.null(assistant@contents[[3]]@tool))
  expect_equal(assistant@tokens, c(10, 5, 3))
  expect_equal(assistant@duration, 1.5)
  expect_equal(assistant@finish_reason, "tool_use")

  tool_turn <- turns[[3]]
  result <- tool_turn@contents[[1]]
  expect_s3_class(result, "ellmer::ContentToolResult")
  expect_equal(result@value, "3")
  expect_equal(result@request@id, "call_1")

  expect_equal(turns[[4]]@finish_reason, "success")
  expect_equal(turns[[4]]@tokens, c(20, 6, 10))
})

test_that("vitals_log_read reads logs written by Python Inspect", {
  log_file <- system.file(
    "test/inspect/logs",
    "2025-04-07T11-00-30-05-00_arithmetic-with-tool_gKECTBvzvzgtPqQCd3cirF.json",
    package = "vitals"
  )
  skip_if(identical(log_file, ""), "Test log files not available")

  res <- vitals_log_read(log_file, solver_chat = mock_chat_template())

  expect_equal(nrow(res), 2)
  expect_equal(res$input, c("What's 71+31?", "What's 91+13?"))
  expect_equal(res$score, c("C", "C"))

  turns <- res$solver_chat[[1]]$get_turns()
  expect_length(turns, 4)
  expect_s3_class(turns[[2]]@contents[[2]], "ellmer::ContentToolRequest")
  expect_s3_class(turns[[3]]@contents[[1]], "ellmer::ContentToolResult")
  expect_equal(
    turns[[3]]@contents[[1]]@request@id,
    turns[[2]]@contents[[2]]@id
  )
  expect_equal(turns[[2]]@finish_reason, "tool_use")
  expect_gt(turns[[2]]@tokens[1], 0)
})

test_that("vitals_log_read resolves attachment references", {
  log_file <- system.file(
    "test/inspect/logs",
    "2025-06-04T10-45-58-05-00_system-prompt_FzH5aCHPGhLT6CGuF5Xdmj.json",
    package = "vitals"
  )
  skip_if(identical(log_file, ""), "Test log files not available")

  res <- vitals_log_read(log_file, solver_chat = mock_chat_template())

  turn_texts <- purrr::map_chr(res$solver_chat[[1]]$get_turns(), function(x) {
    x@text
  })
  expect_false(any(grepl("attachment://", turn_texts, fixed = TRUE)))
})

test_that("vitals_log_read reconstructs scorer chats", {
  skip_on_cran()
  tmp_dir <- withr::local_tempdir()

  tsk <- example_task()
  log_path <- tsk$log(tmp_dir)

  res <- vitals_log_read(
    log_path,
    solver_chat = mock_chat_template(),
    scorer_chat = mock_chat_template()
  )

  expect_true("scorer_chat" %in% names(res))
  scorer <- res$scorer_chat[[1]]
  expect_equal(scorer$get_model(), "claude-sonnet-4-5-20250929")

  scorer_turns <- scorer$get_turns()
  expect_length(scorer_turns, 2)
  expect_match(scorer_turns[[1]]@text, "assessing a submitted answer")
  expect_match(scorer_turns[[2]]@text, "GRADE:")
})

test_that("vitals_log_read errors informatively", {
  expect_snapshot(error = TRUE, vitals_log_read("no-such-file.json"))

  skip_on_cran()
  tmp_dir <- withr::local_tempdir()
  log_path <- example_task()$log(tmp_dir)
  expect_snapshot(
    error = TRUE,
    vitals_log_read(log_path, solver_chat = "not a chat")
  )
})
