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
      import_inspect_log(path, inputs = "What is the capital of France? Reply with just the city name.",
        chat = mock_chat_template())
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

# check_inspect_agent_deps checks docker for configured sandboxes

    Code
      check_inspect_agent_deps(c("docker", "compose.yaml"))
    Condition
      Error:
      ! Coding agent solvers require Docker when `sandbox` is a Docker sandbox.
      i Install Docker Desktop or similar and ensure `docker` is on your `PATH`.

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

---

    Code
      claude_code(mock_chat_template(), limit = 1, log_samples = FALSE)
    Condition
      Error in `claude_code()`:
      ! `limit` and `log_samples` can't be set on an agent solver.
      i The solver needs one logged sample per input, and these arguments can leave the log with fewer.
      i To evaluate a subset of the dataset, subset it before passing it to Task (`?vitals::Task()`).

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

# inspect_model_string rejects providers Inspect can't serve

    Code
      inspect_model_string(mock_chat_template(model = "some-model"))
    Condition
      Error:
      ! `solver_chat` uses the "OpenAI-compatible" provider, which Inspect can't serve to the agent.
      i Supported providers: `ellmer::chat_anthropic()`, `ellmer::chat_openai()`, `ellmer::chat_google_gemini()`, `ellmer::chat_google_vertex()`, `ellmer::chat_aws_bedrock()`, `ellmer::chat_groq()`, `ellmer::chat_mistral()`, `ellmer::chat_ollama()`, `ellmer::chat_openrouter()`, and `ellmer::chat_perplexity()`.

