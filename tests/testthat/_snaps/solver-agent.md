# claude_code checks inputs

    Code
      claude_code(mock_chat_template(), "boop")
    Condition
      Error in `claude_code()`:
      ! All arguments in `...` must be named.

---

    Code
      claude_code(mock_chat_template(), sandbox = c("docker", 1, 2))
    Condition
      Error in `claude_code()`:
      ! `sandbox` must be a sandbox type or a pair of sandbox type and configuration file, e.g. `c("docker", "compose.yaml")`.

---

    Code
      claude_code(version = 1)
    Condition
      Error in `claude_code()`:
      ! `version` must be a single string, not the number 1.

# agent solvers check their chat when they solve

    Code
      solver("What's 2+2?")
    Condition
      Error in `solver()`:
      ! `solver_chat` must be a <Chat>, not a string

---

    Code
      solver("What's 2+2?")
    Condition
      Error in `solver()`:
      ! `solver_chat` can't have tools registered.
      i The agent runs in a sandbox with its own tools; tools registered with ellmer aren't available to it.

# import_inspect_log errors informatively on failed evals

    Code
      import_inspect_log(path, inputs = claude_code_input, chat = mock_chat_template())
    Condition
      Error:
      ! The Inspect eval powering this solver did not complete successfully (status "error").
      i sandbox exploded
      i 1 sample transcript completed before the failure and remains in the log.
      i See '<log_path>' for the full log.

# import_inspect_log errors informatively on sample count mismatch

    Code
      import_inspect_log(path, inputs = c("one", "two"), chat = mock_chat_template())
    Condition
      Error:
      ! The Inspect log contains 1 sample but 2 inputs were provided.
      i See '<log_path>' for the full log.

# agent solvers reject reserved arguments

    Code
      claude_code(mock_chat_template(), epochs = 2)
    Condition
      Error in `claude_code()`:
      ! `epochs` can't be set on an agent solver.
      i Pass it to Task (`?vitals::Task()`)'s `$eval()` method instead.

---

    Code
      codex(mock_chat_template(), log_dir = "logs")
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

# with_chat_args errors on params Inspect can't pass along

    Code
      with_chat_args(list(agent = list(), eval = list()), chat, config_names = "temperature")
    Condition
      Error:
      ! `solver_chat` sets `made_up`, which Inspect can't pass along to the model serving the agent.
      i Drop it from `ellmer::params()`.

