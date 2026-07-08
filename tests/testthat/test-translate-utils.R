test_that("eval_log_filename sanitizes colons in model names (#207)", {
  eval_log <- list(eval = list(
    created = "2025-02-08T15:51:00-06:00",
    task_id = "dataset/ministral-3:14b/abc123"
  ))
  filename <- eval_log_filename(eval_log)
  expect_false(grepl(":", filename))
  expect_equal(
    filename,
    "2025-02-08T15-51-00-06-00_dataset-ministral-3-14b-abc123.json"
  )
})

test_that("provider_prefix resolves to an ellmer chat function", {
  provider_names <- c(
    "Anthropic",
    "OpenAI",
    "Google/Gemini",
    "LM Studio",
    "PortkeyAI"
  )
  for (name in provider_names) {
    fn <- paste0("chat_", provider_prefix(name))
    expect_true(
      is.function(get0(fn, envir = asNamespace("ellmer"))),
      label = paste0("ellmer::", fn, "() exists")
    )
  }
})

test_that("type_to_schema drops ignored arguments and keeps descriptions", {
  type <- ellmer::type_object(
    "An object.",
    a = ellmer::type_number("First number."),
    b = ellmer::type_ignore()
  )
  schema <- type_to_schema(type)
  expect_equal(schema$description, "An object.")
  expect_named(schema$properties, "a")
  expect_equal(schema$required, list("a"))
})

test_that("translate_to_model_usage works with example turns", {
  skip_on_cran()
  ellmer_usage <- translate_to_model_usage(example_ellmer_solver())

  inspect_usage <- example_inspect_log()[["samples"]][[1]][["model_usage"]]

  expect_type(ellmer_usage, "list")
  expect_equal(names(ellmer_usage), chat_provider_model(example_ellmer_solver()))
  expect_equal(length(ellmer_usage[[1]]), length(inspect_usage[[1]]))
})

test_that("translate_to_output works with example turns", {
  skip_on_cran()
  ellmer_output <- translate_to_output(example_ellmer_solver())

  inspect_output <- example_inspect_log()[["samples"]][[1]][["output"]]

  expect_equal(names(ellmer_output), names(inspect_output))
  expect_equal(length(ellmer_output$usage), length(ellmer_output$usage))
})
