# claude_code checks inputs

    Code
      claude_code()
    Condition
      Error in `claude_code()`:
      ! `model` must be a single string, not absent.

---

    Code
      claude_code(model = 1)
    Condition
      Error in `claude_code()`:
      ! `model` must be a single string, not the number 1.

---

    Code
      claude_code(model = "anthropic/some-model", agent_args = list(1))
    Condition
      Error in `claude_code()`:
      ! `agent_args` must be a named list.

# codex checks inputs

    Code
      codex()
    Condition
      Error in `codex()`:
      ! `model` must be a single string, not absent.

---

    Code
      codex(model = "openai/some-model", version = 1)
    Condition
      Error in `codex()`:
      ! `version` must be a single string, not the number 1.

# import_inspect_log errors informatively on failed evals

    Code
      import_inspect_log(path, inputs = claude_code_input)
    Condition
      Error:
      ! The Inspect eval powering this solver did not complete successfully (status "error").
      i sandbox exploded
      i 1 sample transcript completed before the failure and remains in the log.
      i See '<log_path>' for the full log.

# import_inspect_log errors informatively on sample count mismatch

    Code
      import_inspect_log(path, inputs = c("one", "two"))
    Condition
      Error:
      ! The Inspect log contains 1 sample but 2 inputs were provided.
      i See '<log_path>' for the full log.

# agent solvers reject reserved arguments

    Code
      claude_code(model = "anthropic/some-model", agent_args = list(version = "2.1.37"))
    Condition
      Error in `claude_code()`:
      ! Pass `version` as its own argument rather than in `agent_args`.

---

    Code
      claude_code(model = "anthropic/some-model", epochs = 2)
    Condition
      Error in `claude_code()`:
      ! `epochs` can't be set on an agent solver.
      i Pass it to Task (`?vitals::Task()`)'s `$eval()` method instead.

---

    Code
      codex(model = "openai/some-model", log_dir = "logs")
    Condition
      Error in `codex()`:
      ! `log_dir` is determined by the solver and can't be set.

