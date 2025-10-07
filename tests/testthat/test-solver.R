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
