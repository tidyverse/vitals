test_that("generate works", {
  vcr::local_cassette("solver-generate")
  key_get("OPENAI_API_KEY")
  library(ellmer)

  res <- generate(chat_openai(model = "gpt-4.1-nano"))
  expect_contains(class(res), "function")

  chat_res <- res(list("hey", "hi", "hello"))

  expect_length(chat_res, 2)
  expect_length(chat_res[["result"]], 3)
  expect_length(chat_res[["solver_chat"]], 3)
  expect_type(chat_res[["result"]][[1]], "character")
  expect_s3_class(chat_res[["solver_chat"]][[1]], "Chat")
})

test_that("generate() allows NULL default model", {
  res <- generate()
  expect_contains(class(res), "function")
  expect_snapshot(res(), error = TRUE)
})

test_that("generate_structured works", {
  vcr::local_cassette("solver-generate-structured")
  key_get("ANTHROPIC_API_KEY")
  library(ellmer)

  type_answer <- type_object(
    answer = type_string("The answer to the math question")
  )

  res <- generate_structured(
    solver_chat = chat_anthropic(model = "claude-sonnet-4-20250514"),
    type = type_answer
  )

  expect_contains(class(res), "function")

  chat_res <- res(list("What is 2+2?", "What is 3+3?"))

  expect_length(chat_res, 3)
  expect_length(chat_res[["result"]], 2)
  expect_type(chat_res[["result"]][[1]], "character")
  expect_length(chat_res[["solver_chat"]], 2)
  expect_s3_class(chat_res[["solver_chat"]][[1]], "Chat")
  expect_length(chat_res[["solver_metadata"]], 2)
  expect_true("answer" %in% names(chat_res[["solver_metadata"]][[1]]))
})

test_that("generate_structured() allows NULL default model", {
  res <- generate_structured()
  expect_contains(class(res), "function")
  expect_snapshot(res(), error = TRUE)
})

test_that("generate_structured produces valid logs", {
  vcr::local_cassette("solver-generate-structured-task")
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)
  library(ellmer)

  type_answer <- type_object(
    answer = type_string("The numeric answer to the math question")
  )

  simple_addition <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate_structured(
      solver_chat = chat_anthropic(model = "claude-sonnet-4-20250514"),
      type = type_answer
    ),
    scorer = model_graded_qa()
  )

  tsk$eval()
  expect_valid_log(tsk$log())

  samples <- tsk$get_samples()
  expect_type(samples$result, "character")
  expect_length(samples$result, 2)
  expect_length(samples$solver_chat, 2)
  expect_s3_class(samples$solver_chat[[1]], "Chat")
  expect_length(samples$solver_metadata, 2)
  expect_true("answer" %in% names(samples$solver_metadata[[1]]))
})
