# Task R6 class works

    Code
      tsk
    Output
      An evaluation task simple-addition.

---

    Code
      tsk
    Output
      An evaluation task simple-addition.
      Explore interactively with `.last_task$view()`.

# check_dataset works

    Code
      Task$new(dataset = data.frame(input = 1), solver = function() { }, scorer = function()
        { })
    Condition
      Error in `initialize()`:
      ! `dataset` is missing required column target.

---

    Code
      Task$new(dataset = data.frame(target = 1), solver = function() { }, scorer = function()
        { })
    Condition
      Error in `initialize()`:
      ! `dataset` is missing required column input.

---

    Code
      Task$new(dataset = data.frame(x = 1), solver = function() { }, scorer = function()
        { })
    Condition
      Error in `initialize()`:
      ! `dataset` is missing required columns input and target.

# Task errors informatively with duplicate ids

    Code
      Task$new(dataset = d, solver = function() { }, scorer = function() { })
    Condition
      Error in `initialize()`:
      ! Duplicated values found in the id column. Each ID must be unique.

# task errors informatively with bad metrics

    Code
      tsk <- Task$new(dataset = simple_addition, solver = generate(ellmer::chat_openai(
        model = "gpt-4.1-nano")), scorer = function(...) {
        list(score = factor(c("C", "C"), levels = c("I", "P", "C")))
      }, metrics = function(scores) {
        mean(scores == "C") * 100
      })
    Condition
      Error in `initialize()`:
      ! `metrics` must be a named list of functions or NULL, not a function

---

    Code
      tsk$set_metrics(function(...) "boop bop")
    Condition
      Error:
      ! `metrics` must be a named list of functions or NULL, not a function

---

    Code
      tsk$set_metrics(list(bad_metric = function(scores) "this is not a numeric"))
      tsk$eval()
    Condition
      Error in `measure()`:
      ! Each metric function must return a single numeric value
      `bad_metric()` returned a string

# Task errors informatively with bad solver output

    Code
      tsk$solve()
    Condition
      Error in `$solve()`:
      ! `solver` must return slots result and solver_chat.

# Task detects non-Chat objects in solver_chat

    Code
      tsk$solve()
    Condition
      Error in `$solve()`:
      ! Elements in the solver_chat output from `solver` must be ellmer Chat objects, not a string.

# Task errors informatively with bad scorer output

    Code
      tsk$eval()
    Condition
      Error in `$score()`:
      ! `scorer` must return a list with (at least) the slot score.

# Task detects non-Chat objects in scorer_chat

    Code
      tsk$eval()
    Condition
      Error in `$score()`:
      ! Elements in the scorer_chat output from `scorer` must be ellmer Chat objects, not a string.

# eval errors with unnamed arguments

    Code
      tsk$eval("unnamed_arg")
    Condition
      Error in `$eval()`:
      ! All arguments in `...` must be named.

# eval errors when argument matches neither function and neither has ellipses

    Code
      tsk$eval(unmatched_param = "error")
    Condition
      Error in `$eval()`:
      ! Argument `unmatched_param` does not match any parameter in the solver or scorer functions.

