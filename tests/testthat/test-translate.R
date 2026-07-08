test_that("expect_valid_log fails when log file is nonsense", {
  # use a file name that "looks like" it could be a real Inspect log so that
  # Inspect tries to read it
  tmp_dir <- withr::local_tempdir()
  tmp_file <- file.path(
    tmp_dir,
    "2025-04-02T16-49-36-05-00_simpleaddition_e1e56aeef83a77f6392787.json"
  )
  file.create(tmp_file)
  writeLines(c("beep", "bop", "boop"), tmp_file)

  expect_error(
    suppressWarnings(expect_valid_log(tmp_file)),
    regexp = "Expecting value: line 1 column 1"
  )
})

test_that("vitals writes valid eval logs (basic, openai)", {
  vcr::local_cassette("translate-openai-basic")
  key_get("OPENAI_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  simple_addition <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(ellmer::chat_openai(model = "gpt-4.1-nano")),
    scorer = model_graded_qa()
  )
  tsk$eval()
  expect_valid_log(tsk$log())
})

test_that("vitals writes valid eval logs (basic, claude)", {
  vcr::local_cassette("translate-anthropic-basic")
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  simple_addition <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(ellmer::chat_claude(
      model = "claude-sonnet-4-5-20250929"
    )),
    scorer = model_graded_qa()
  )
  tsk$eval()
  expect_valid_log(tsk$log())
})

test_that("vitals writes valid eval logs (basic, gemini)", {
  vcr::local_cassette("translate-google-basic")
  key_get("GOOGLE_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  simple_addition <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(ellmer::chat_google_gemini(model = "gemini-2.0-flash")),
    scorer = model_graded_qa()
  )
  tsk$eval()
  expect_valid_log(tsk$log())
})


test_that("vitals writes valid eval logs (solver tool calls, claude)", {
  vcr::local_cassette("translate-anthropic-tool-calls")
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)
  library(ellmer)

  current_date <- tibble::tibble(
    input = c("What's the current date?"),
    target = c("2024-01-01")
  )

  ch <- chat_claude(model = "claude-sonnet-4-5-20250929")
  ch$register_tool(tool(
    function() "2024-01-01",
    name = "get_current_date",
    description = "Return the current date"
  ))

  tsk <- Task$new(
    dataset = current_date,
    solver = generate(ch),
    scorer = function(samples) {
      list(score = factor("C", levels = c("I", "C"), ordered = TRUE))
    }
  )
  tsk$eval()
  expect_valid_log(tsk$log())
})

test_that("vitals writes valid eval logs (solver errors on tool call, claude)", {
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)
  library(ellmer)

  current_date <- tibble::tibble(
    input = c("What's the current date?"),
    target = c("2024-01-01")
  )

  ch <- chat_claude(model = "claude-sonnet-4-5-20250929")
  ch$register_tool(
    tool(
      function() stop("Couldn't find the date"),
      name = "get_current_date",
      description = "Return the current date"
    )
  )

  tsk <- Task$new(
    dataset = current_date,
    solver = generate(ch),
    scorer = function(samples) {
      list(score = factor("C", levels = c("I", "C"), ordered = TRUE))
    }
  )

  # a tool call will fail here and raise a warning; this is intentional.
  # since raised from ellmer, we don't expect anything specific about it.
  suppressWarnings(tsk$eval())

  log_file <- list.files(tmp_dir, full.names = TRUE)
  expect_gte(length(log_file), 1)

  expect_valid_log(log_file[1])
})

test_that("vitals writes valid eval logs with reasoning and typed tools", {
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
      finish_reason = "tool_use"
    ),
    ellmer::UserTurn(contents = list(
      ellmer::ContentToolResult(value = 3, request = request)
    )),
    ellmer::AssistantTurn(
      contents = list(ellmer::ContentText("The answer is 3.")),
      tokens = c(20, 6, 10),
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
  expect_valid_log(log_path)

  log <- jsonlite::fromJSON(log_path, simplifyVector = FALSE)
  expect_equal(log$eval$model, "openai_compatible/test-model")

  sample <- log$samples[[1]]
  assistant <- sample$messages[[2]]
  expect_equal(assistant$content[[1]]$type, "reasoning")
  expect_equal(assistant$content[[1]]$reasoning, "I should use the tool.")
  expect_equal(assistant$content[[1]]$signature, "sig")

  model_events <- purrr::keep(
    sample$events,
    function(event) identical(event$event, "model")
  )
  expect_equal(model_events[[1]]$output$choices[[1]]$stop_reason, "tool_calls")
  expect_equal(model_events[[2]]$output$choices[[1]]$stop_reason, "stop")
  expect_equal(model_events[[1]]$output$usage$input_tokens_cache_read, 3)
  expect_equal(model_events[[1]]$model, "openai_compatible/test-model")

  tool_schema <- model_events[[1]]$tools[[1]]$parameters
  expect_named(tool_schema$properties, c("a", "b"))
  expect_equal(tool_schema$properties$a$type, "number")
})

test_that("repeated long content is condensed into sample attachments", {
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  long_answer <- paste(
    rep("All work and no play makes Jack a dull boy.", 10),
    collapse = " "
  )
  image_uri <- paste0("data:image/png;base64,", strrep("abcd", 50))

  chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.com",
    model = "test-model",
    credentials = function() "fake-key"
  )
  chat$set_turns(list(
    ellmer::UserTurn(contents = list(
      ellmer::ContentText("Describe this image at length."),
      ellmer::ContentImageInline(type = "image/png", data = strrep("abcd", 50))
    )),
    ellmer::AssistantTurn(
      contents = list(ellmer::ContentText(long_answer)),
      finish_reason = "success"
    ),
    ellmer::UserTurn("Again, please."),
    ellmer::AssistantTurn(
      contents = list(ellmer::ContentText(long_answer)),
      finish_reason = "success"
    )
  ))

  tsk <- Task$new(
    dataset = tibble::tibble(input = "Describe this image.", target = "A story."),
    solver = function(inputs) {
      list(result = long_answer, solver_chat = list(chat))
    },
    scorer = function(samples) {
      list(score = factor("C", levels = c("I", "C"), ordered = TRUE))
    }
  )
  tsk$eval()
  log_path <- tsk$log()
  expect_valid_log(log_path)

  log <- jsonlite::fromJSON(log_path, simplifyVector = FALSE)
  sample <- log$samples[[1]]

  expect_gt(length(sample$attachments), 0)
  expect_true(long_answer %in% unlist(sample$attachments))
  expect_true(image_uri %in% unlist(sample$attachments))

  events_json <- jsonlite::toJSON(sample$events, auto_unbox = TRUE)
  expect_false(grepl(long_answer, events_json, fixed = TRUE))
  expect_true(grepl("attachment://", events_json, fixed = TRUE))

  expect_equal(sample$messages[[2]]$content[[1]]$text, long_answer)
  expect_match(sample$messages[[1]]$content[[2]]$image, "^attachment://")

  res <- vitals_log_read(
    log_path,
    solver_chat = ellmer::chat_openai_compatible(
      base_url = "https://example.com",
      model = "placeholder",
      credentials = function() "fake-key"
    )
  )
  turns <- res$solver_chat[[1]]$get_turns()
  expect_equal(turns[[2]]@text, long_answer)
  expect_equal(turns[[1]]@contents[[2]]@data, strrep("abcd", 50))
})

test_that("tool errors are logged in the message error field", {
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  request <- ellmer::ContentToolRequest(
    id = "call_1",
    name = "add",
    arguments = list(a = 1, b = 2)
  )

  chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.com",
    model = "test-model",
    credentials = function() "fake-key"
  )
  chat$set_turns(list(
    ellmer::UserTurn("What is 1 + 2?"),
    ellmer::AssistantTurn(
      contents = list(request),
      finish_reason = "tool_use"
    ),
    ellmer::UserTurn(contents = list(
      ellmer::ContentToolResult(
        error = "tool add is unavailable",
        request = request
      )
    )),
    ellmer::AssistantTurn(
      contents = list(ellmer::ContentText("I couldn't compute that.")),
      finish_reason = "success"
    )
  ))

  tsk <- Task$new(
    dataset = tibble::tibble(input = "What is 1 + 2?", target = "3"),
    solver = function(inputs) {
      list(result = "I couldn't compute that.", solver_chat = list(chat))
    },
    scorer = function(samples) {
      list(score = factor("I", levels = c("I", "C"), ordered = TRUE))
    }
  )
  tsk$eval()
  log_path <- tsk$log()
  expect_valid_log(log_path)

  log <- jsonlite::fromJSON(log_path, simplifyVector = FALSE)
  tool_message <- purrr::detect(
    log$samples[[1]]$messages,
    function(message) identical(message$role, "tool")
  )
  expect_equal(tool_message$error$message, "tool add is unavailable")
})

test_that("vitals writes valid logs with numeric solver results (#145)", {
  vcr::local_cassette("translate-numeric-results")
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  simple_dataset <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  chat <- ellmer::chat_claude(model = "claude-sonnet-4-5-20250929")
  chat$chat("Hey!", echo = FALSE)

  simple_solver <- function(inputs) {
    list(
      result = rep(1.5, length(inputs)),
      solver_chat = lapply(inputs, function(x) {
        chat
      })
    )
  }

  tsk <- Task$new(
    dataset = simple_dataset,
    solver = simple_solver,
    scorer = model_graded_qa()
  )

  tsk$eval()
  log_path <- tsk$log()
  expect_valid_log(log_path)
})

test_that("as_metadata can make lists into a named vector (#69)", {
  res <- as_metadata(mtcars[1:2, 1:2])
  expect_type(res, "list")
  expect_named(res, c("mpg", "cyl"))
  expect_snapshot(res)

  res <- as_metadata(tibble(x = list(list(a = 1, b = 2)), y = 3))
  expect_type(res, "list")
  expect_named(res, c("x", "y"))
  expect_snapshot(res)

  res <- as_metadata(list(1:3, b = 2))
  expect_type(res, "list")
  expect_named(res, c("1", "b"))
  expect_snapshot(res)

  res <- as_metadata(list(1:3, b = 2))
  expect_type(res, "list")
  expect_named(res, c("1", "b"))
  expect_snapshot(res)

  vec <- c(a = 1, b = 2)
  expect_equal(as_metadata(vec), as.list(vec))
})
