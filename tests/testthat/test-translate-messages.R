test_that("translate_to_messages works with example turns", {
  ellmer_messages <- translate_to_messages(example_ellmer_solver()$set_system_prompt(
    NULL
  ))

  inspect_messages <- example_inspect_log()[["samples"]][[1]][["messages"]]

  zap_id <- function(l) {
    l[["id"]] <- NULL
    l
  }
  expect_equal(
    purrr::map(ellmer_messages, zap_id),
    purrr::map(inspect_messages, zap_id)
  )
})

test_that("translate_to_messages handles image inputs", {
  key_get("ANTHROPIC_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)
  library(ellmer)

  dataset <- tibble::tibble(
    input = "What does this image show?",
    target = "The image shows a bike."
  )

  image_solver <- function(
    inputs,
    solver_chat = chat_anthropic(model = "claude-sonnet-4-5-20250929")
  ) {
    image_file <- system.file("test/x.png", package = "vitals")
    ch <- solver_chat$clone()
    ch$chat(inputs[1], content_image_file(image_file), echo = FALSE)
    list(result = ch$last_turn()@text, solver_chat = list(ch))
  }

  tsk <- Task$new(
    dataset = dataset,
    solver = image_solver,
    scorer = model_graded_qa()
  )

  tsk$eval()
  expect_valid_log(tsk$log())
})


test_that("logs including system prompts are compatible with inspect", {
  vcr::local_cassette("translate-messages-system-prompts")
  key_get("OPENAI_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {})
  local_mocked_bindings(interactive = function(...) FALSE)

  library(ellmer)

  simple_addition <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(chat_openai(
      system_prompt = "Be terse.",
      model = "gpt-4.1-nano"
    )),
    scorer = model_graded_qa()
  )

  tsk$eval()
  expect_valid_log(tsk$log())
  expect_true(any(grepl("Be terse", readLines(tsk$log()))))
})
