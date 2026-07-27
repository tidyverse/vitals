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
      claude_code(model = "anthropic/some-model", "boop")
    Condition
      Error in `claude_code()`:
      ! All arguments in `...` must be named.

---

    Code
      claude_code(model = "anthropic/some-model", sandbox = c("docker", 1, 2))
    Condition
      Error in `claude_code()`:
      ! `sandbox` must be a sandbox type or a pair of sandbox type and configuration file, e.g. `c("docker", "compose.yaml")`.

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

# split_agent_args routes arguments by signature

    Code
      split_agent_args(list(not_an_argument = 1), agent_params = "system_prompt",
      eval_params = "max_samples", call = rlang::current_env())
    Condition
      Error:
      ! `not_an_argument` is not an argument of the agent or of Python Inspect's `eval()`.
      i See <https://meridianlabs-ai.github.io/inspect_swe/reference/> for the agent's arguments.

