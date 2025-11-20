test_that("is_positron works", {
  # default when unset
  withr::local_envvar(POSITRON = "")
  expect_false(is_positron())

  # explicit values
  withr::local_envvar(POSITRON = "1")
  expect_true(is_positron())

  withr::local_envvar(POSITRON = "0")
  expect_false(is_positron())
})

test_that("is_testing works", {
  # reflects current testing status
  expect_equal(is_testing(), identical(Sys.getenv("TESTTHAT"), "true"))

  # can be overridden
  withr::local_envvar(TESTTHAT = "true")
  expect_true(is_testing())

  withr::local_envvar(TESTTHAT = "false")
  expect_false(is_testing())
})

test_that("check_inherits works", {
  # errors informatively with wrong class
  expect_snapshot(check_inherits(1, "list"), error = TRUE)
  expect_snapshot(check_inherits(1, "list", x_arg = "my_arg"), error = TRUE)

  # no condition otherwise
  expect_null(check_inherits(list(), "list"))
  expect_null(check_inherits(mtcars, c("data.frame", "list")))
})

test_that("solver_chat works", {
  skip_on_cran()
  example_sample <- example_task()$get_samples()[1, , drop = FALSE]

  res <- solver_chat(example_sample)
  expect_s3_class(res, "Chat")
  expect_equal(res$get_turns(), list())
})

test_that("check_log_dir warns informatively", {
  withr::local_envvar(VITALS_LOG_DIR = NA)
  expect_snapshot(
    res <- Task$new(
      tibble(input = 1, target = 1),
      function() {},
      function() {}
    )
  )
})
