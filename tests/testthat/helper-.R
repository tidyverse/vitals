mock_chat_template <- function(model = "placeholder", ...) {
  ellmer::chat_openai_compatible(
    base_url = "https://example.com",
    model = model,
    credentials = function() "fake-key",
    ...
  )
}

example_tool_fixture <- function() {
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

  chat <- mock_chat_template(model = "test-model", system_prompt = "Be terse.")
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

  task <- Task$new(
    dataset = tibble(input = "What is 1 + 2?", target = "3"),
    solver = function(inputs) {
      list(result = "The answer is 3.", solver_chat = list(chat))
    },
    scorer = function(samples) {
      list(score = factor("C", levels = c("I", "C"), ordered = TRUE))
    }
  )

  list(task = task, tool_def = tool_def)
}

mock_chat_turns <- function(..., system_prompt = NULL, model = "test-model") {
  chat <- ellmer::chat_openai_compatible(
    base_url = "https://example.com",
    model = model,
    system_prompt = system_prompt,
    credentials = function() "fake-key"
  )
  pairs <- list(...)
  turns <- list()
  for (pair in pairs) {
    turns <- c(
      turns,
      list(
        ellmer::UserTurn(contents = list(ellmer::ContentText(pair$user))),
        ellmer::AssistantTurn(
          contents = list(ellmer::ContentText(pair$assistant))
        )
      )
    )
  }
  chat$set_turns(turns)
  chat
}

example_ellmer_solver <- function() {
  mock_chat_turns(list(user = "What's 2+2?", assistant = "2+2=4"))
}

# a log actually written by Python Inspect
example_inspect_log <- function() {
  log_path <- system.file(
    "test/inspect/logs/2025-03-24T10-39-36-05-00_simple-arithmetic_fQ9mYnqZFhtEuUenPpJgKL.json",
    package = "vitals"
  )
  if (identical(log_path, "")) {
    testthat::skip("Test log files not available")
  }
  eval_log_read(log_path)
}

example_task <- function(solved = TRUE, scored = TRUE) {
  # loads a cached `tsk` with example output.
  # regenerate with `inst/regenerate-example-objects.R`
  load(
    system.file(
      "test/example-task.rda",
      package = "vitals"
    )
  )

  simple_addition <- tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  res <- Task$new(
    dataset = simple_addition,
    solver = function(...) {},
    scorer = function(...) {}
  )

  if (!solved) {
    return(res)
  }

  res$.__enclos_env__$private$samples$result <- tsk$get_samples()$result
  res$.__enclos_env__$private$samples$solver_chat <- tsk$get_samples()$solver_chat
  res$.__enclos_env__$private$solved <- TRUE

  if (!scored) {
    return(res)
  }

  res$.__enclos_env__$private$samples$score <- tsk$get_samples()$score
  res$.__enclos_env__$private$samples$scorer_chat <- tsk$get_samples()$scorer_chat
  res$.__enclos_env__$private$samples$scorer <- tsk$get_samples()$scorer
  res$.__enclos_env__$private$scored <- TRUE

  res
}
