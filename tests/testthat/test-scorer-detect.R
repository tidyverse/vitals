test_that("detect_includes works", {
  tsk <- example_task(scored = FALSE)
  tsk$set_scorer(detect_includes())
  tsk$score()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_true(is.ordered(tsk$get_samples()$score))
  expect_equal(as.character(tsk$get_samples()$score), c("C", "C"))
  # TODO: include and test for `metadata` slots (here and in model-based)

  simple_df <- tibble::tibble(
    input = c("Question 1", "Question 2"),
    result = c("The answer is C", "The answer is D"),
    target = c("c", "d")
  )

  tsk_insensitive <- Task$new(
    dataset = simple_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_insensitive$.__enclos_env__$private$solved <- TRUE
  tsk_insensitive$set_scorer(detect_includes(case_sensitive = FALSE))
  tsk_insensitive$score()

  expect_s3_class(tsk_insensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_insensitive$get_samples()$score))
  expect_equal(as.character(tsk_insensitive$get_samples()$score), c("C", "C"))

  tsk_sensitive <- Task$new(
    dataset = simple_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_sensitive$.__enclos_env__$private$solved <- TRUE
  tsk_sensitive$set_scorer(detect_includes(case_sensitive = TRUE))
  tsk_sensitive$score()
  expect_s3_class(tsk_sensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_sensitive$get_samples()$score))
  expect_equal(as.character(tsk_sensitive$get_samples()$score), c("I", "I"))
})

test_that("detect_match works", {
  tsk <- example_task(scored = FALSE)
  tsk$set_scorer(detect_match())
  tsk$score()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_true(is.ordered(tsk$get_samples()$score))
  expect_equal(as.character(tsk$get_samples()$score), c("C", "C"))

  simple_df <- tibble::tibble(
    input = c("Question 1", "Question 2"),
    result = c("The answer is C", "The answer is D"),
    target = c("c", "d")
  )

  tsk_insensitive <- Task$new(
    dataset = simple_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_insensitive$.__enclos_env__$private$solved <- TRUE
  tsk_insensitive$set_scorer(detect_match(case_sensitive = FALSE))
  tsk_insensitive$score()
  expect_s3_class(tsk_insensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_insensitive$get_samples()$score))
  expect_equal(as.character(tsk_insensitive$get_samples()$score), c("C", "C"))

  tsk_sensitive <- Task$new(
    dataset = simple_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_sensitive$.__enclos_env__$private$solved <- TRUE
  tsk_sensitive$set_scorer(detect_match(case_sensitive = TRUE))
  tsk_sensitive$score()
  expect_s3_class(tsk_sensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_sensitive$get_samples()$score))
  expect_equal(as.character(tsk_sensitive$get_samples()$score), c("I", "I"))
})

test_that("detect_pattern works", {
  skip_if(getRversion() > "4.4.3")
  tsk <- example_task(scored = FALSE)
  tsk$set_scorer(detect_pattern("(\\d+)\\s*=\\s*(\\d+)"))
  tsk$score()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_true(is.ordered(tsk$get_samples()$score))
  expect_equal(as.character(tsk$get_samples()$score), c("C", "C"))

  case_df <- tibble::tibble(
    input = c("Question 1", "Question 2"),
    result = c("The answer contains C", "The answer contains D"),
    target = c("c", "d")
  )

  tsk_insensitive <- Task$new(
    dataset = case_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_insensitive$.__enclos_env__$private$solved <- TRUE
  tsk_insensitive$set_scorer(detect_pattern(
    "contains\\s+([A-Za-z])",
    case_sensitive = FALSE
  ))
  tsk_insensitive$score()
  expect_s3_class(tsk_insensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_insensitive$get_samples()$score))
  expect_equal(as.character(tsk_insensitive$get_samples()$score), c("C", "C"))

  tsk_sensitive <- Task$new(
    dataset = case_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_sensitive$.__enclos_env__$private$solved <- TRUE
  tsk_sensitive$set_scorer(detect_pattern(
    "contains\\s+([A-Za-z])",
    case_sensitive = TRUE
  ))
  tsk_sensitive$score()
  expect_s3_class(tsk_sensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_sensitive$get_samples()$score))
  expect_equal(as.character(tsk_sensitive$get_samples()$score), c("I", "I"))

  all_df <- tibble::tibble(
    input = c("Question 1", "Question 2"),
    result = c(
      "Found colors red and blue",
      "Found colors green and yellow"
    ),
    target = c("red", "green")
  )

  tsk_all_false <- Task$new(
    dataset = all_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_all_false$.__enclos_env__$private$solved <- TRUE
  tsk_all_false$set_scorer(detect_pattern(
    "colors\\s+(\\w+)\\s+and\\s+(\\w+)",
    all = FALSE
  ))
  tsk_all_false$score()
  expect_s3_class(tsk_all_false$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_all_false$get_samples()$score))
  expect_equal(as.character(tsk_all_false$get_samples()$score), c("C", "C"))

  tsk_all_true <- Task$new(
    dataset = all_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_all_true$.__enclos_env__$private$solved <- TRUE
  tsk_all_true$set_scorer(detect_pattern(
    "colors\\s+(\\w+)\\s+and\\s+(\\w+)",
    all = TRUE
  ))
  tsk_all_true$score()
  expect_s3_class(tsk_all_true$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_all_true$get_samples()$score))
  expect_equal(as.character(tsk_all_true$get_samples()$score), c("I", "I"))
})

test_that("detect_exact works", {
  ex_task <- example_task(scored = FALSE)
  exact_df <- tibble::tibble(
    input = ex_task$get_samples()$input,
    result = c(ex_task$get_samples()$target[1], "non-matching output"),
    target = ex_task$get_samples()$target
  )

  tsk <- Task$new(
    dataset = exact_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk$.__enclos_env__$private$solved <- TRUE
  tsk$set_scorer(detect_exact())
  tsk$score()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_true(is.ordered(tsk$get_samples()$score))
  expect_equal(as.character(tsk$get_samples()$score), c("C", "I"))

  case_df <- tibble::tibble(
    input = c("Question 1", "Question 2"),
    result = c("ANSWER: C", "ANSWER: d"),
    target = c("ANSWER: c", "ANSWER: d")
  )

  tsk_insensitive <- Task$new(
    dataset = case_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_insensitive$.__enclos_env__$private$solved <- TRUE
  tsk_insensitive$set_scorer(detect_exact(case_sensitive = FALSE))
  tsk_insensitive$score()
  expect_s3_class(tsk_insensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_insensitive$get_samples()$score))
  expect_equal(as.character(tsk_insensitive$get_samples()$score), c("C", "C"))

  tsk_sensitive <- Task$new(
    dataset = case_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_sensitive$.__enclos_env__$private$solved <- TRUE
  tsk_sensitive$set_scorer(detect_exact(case_sensitive = TRUE))
  tsk_sensitive$score()
  expect_s3_class(tsk_sensitive$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_sensitive$get_samples()$score))
  expect_equal(as.character(tsk_sensitive$get_samples()$score), c("I", "C"))
})

test_that("detect_answer works", {
  ex_task <- example_task(scored = FALSE)
  answer_df <- tibble::tibble(
    input = ex_task$get_samples()$input,
    result = paste("ANSWER:", ex_task$get_samples()$target),
    target = ex_task$get_samples()$target
  )

  tsk <- Task$new(
    dataset = answer_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk$.__enclos_env__$private$solved <- TRUE
  tsk$set_scorer(detect_answer())
  tsk$score()

  expect_s3_class(tsk$get_samples()$score, "factor")
  expect_true(is.ordered(tsk$get_samples()$score))
  expect_equal(as.character(tsk$get_samples()$score), c("C", "C"))

  whitespace_df <- tibble::tibble(
    input = ex_task$get_samples()$input,
    result = paste("ANSWER: ", ex_task$get_samples()$target),
    target = ex_task$get_samples()$target
  )

  tsk_whitespace <- Task$new(
    dataset = whitespace_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_whitespace$.__enclos_env__$private$solved <- TRUE
  tsk_whitespace$set_scorer(detect_answer())
  tsk_whitespace$score()
  expect_s3_class(tsk_whitespace$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_whitespace$get_samples()$score))
  expect_equal(as.character(tsk_whitespace$get_samples()$score), c("C", "C"))

  format_df <- tibble::tibble(
    input = c("Question 1", "Question 2"),
    result = c(
      "The solution is:\nANSWER: The Industrial Revolution",
      "ANSWER: C\nExplanation follows..."
    ),
    target = c(
      "The Industrial Revolution",
      "C"
    )
  )

  tsk_line <- Task$new(
    dataset = format_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_line$.__enclos_env__$private$solved <- TRUE
  tsk_line$set_scorer(detect_answer(format = "line"))
  tsk_line$score()
  expect_s3_class(tsk_line$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_line$get_samples()$score))
  expect_equal(as.character(tsk_line$get_samples()$score), c("C", "I"))

  tsk_word <- Task$new(
    dataset = format_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_word$.__enclos_env__$private$solved <- TRUE
  tsk_word$set_scorer(detect_answer(format = "word"))
  tsk_word$score()
  expect_s3_class(tsk_word$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_word$get_samples()$score))
  expect_equal(as.character(tsk_word$get_samples()$score), c("I", "C"))

  tsk_letter <- Task$new(
    dataset = format_df,
    solver = function() {
    },
    scorer = function() {
    }
  )
  tsk_letter$.__enclos_env__$private$solved <- TRUE
  tsk_letter$set_scorer(detect_answer(format = "letter"))
  tsk_letter$score()
  expect_s3_class(tsk_letter$get_samples()$score, "factor")
  expect_true(is.ordered(tsk_letter$get_samples()$score))
  expect_equal(as.character(tsk_letter$get_samples()$score), c("I", "C"))
})

# In general, we test these scorers completely offline and thus don't `log()`
# as that would require solver chats. Do a "live" test once to ensure that we
# don't assume scorer chats are available while logging. (#77)
test_that("vitals writes valid eval logs (basic, claude)", {
  vcr::local_cassette("scorer-detect-valid-log")
  key_get("OPENAI_API_KEY")
  tmp_dir <- withr::local_tempdir()
  withr::local_envvar(list(VITALS_LOG_DIR = tmp_dir))
  withr::local_options(cli.default_handler = function(...) {
  })
  local_mocked_bindings(interactive = function(...) FALSE)

  simple_addition <- tibble::tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = generate(ellmer::chat_openai(model = "gpt-4.1-nano")),
    scorer = detect_includes()
  )
  tsk$eval()

  expect_valid_log(tsk$log())
})
