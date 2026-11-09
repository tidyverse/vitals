test_that("vitals_bind works", {
  task_1 <- example_task()
  task_2 <- example_task()

  res <- vitals_bind(task_1, task_2)

  expect_s3_class(res, "tbl_df")
  expect_named(res, c("task", "id", "score", "metadata"))
  expect_equal(nrow(res), nrow(task_1$get_samples()) * 2)
  expect_equal(sort(unique(res$task)), c("task_1", "task_2"))

  res_named <- vitals_bind(boop = task_1, bop = task_2)
  expect_equal(sort(unique(res_named$task)), c("boop", "bop"))
})
