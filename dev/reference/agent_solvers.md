# Coding agents as solvers

`claude_code()` and `codex()` are solvers that evaluate the Claude Code
and Codex coding agents on your dataset, allowing you to compare
off-the-shelf agent harnesses against your own with the same scorer.

These solvers bridge to Python Inspect's
[inspect_swe](https://meridianlabs-ai.github.io/inspect_swe/) package,
which runs the agent's command line interface in a Docker sandbox and
proxies its model calls. The agent's transcript is then read back into
ellmer Chat objects so that scoring and logging work exactly as they do
for any other solver.

## Usage

``` r
claude_code(solver_chat = NULL, ..., version = "auto", sandbox = "docker")

codex(solver_chat = NULL, ..., version = "auto", sandbox = "docker")
```

## Arguments

- solver_chat:

  An ellmer chat object, such as from
  [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
  or a zero-argument function that returns one. Its provider and model
  choose the model that powers the agent, and its system prompt and
  [`ellmer::params()`](https://ellmer.tidyverse.org/reference/params.html)
  are passed along to Inspect; the same chat is then reused to
  reconstruct the agent's transcript. The agent reaches the model
  through Inspect rather than directly, so credentials are read on the
  host from the usual environment variables, and any agent can be
  powered by any of the providers Inspect and ellmer agree on:
  [`ellmer::chat_anthropic()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
  [`ellmer::chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html),
  [`ellmer::chat_google_gemini()`](https://ellmer.tidyverse.org/reference/chat_google_gemini.html),
  [`ellmer::chat_google_vertex()`](https://ellmer.tidyverse.org/reference/chat_google_gemini.html),
  [`ellmer::chat_aws_bedrock()`](https://ellmer.tidyverse.org/reference/chat_aws_bedrock.html),
  [`ellmer::chat_groq()`](https://ellmer.tidyverse.org/reference/chat_groq.html),
  [`ellmer::chat_mistral()`](https://ellmer.tidyverse.org/reference/chat_mistral.html),
  [`ellmer::chat_ollama()`](https://ellmer.tidyverse.org/reference/chat_ollama.html),
  [`ellmer::chat_openrouter()`](https://ellmer.tidyverse.org/reference/chat_openrouter.html),
  and
  [`ellmer::chat_perplexity()`](https://ellmer.tidyverse.org/reference/chat_perplexity.html).

- ...:

  Additional named arguments, routed by name to either the inspect_swe
  agent—e.g. `system_prompt`, `disallowed_tools`, `cwd`, or `env`,
  documented in [inspect_swe's
  reference](https://meridianlabs-ai.github.io/inspect_swe/reference/)—or
  to Python Inspect's [`eval()`](https://rdrr.io/r/base/eval.html), e.g.
  `max_samples`, `max_sandboxes`, `time_limit`, or `token_limit`.
  (`epochs` is the exception: pass it to
  [Task](https://vitals.tidyverse.org/dev/reference/Task.md)'s `$eval()`
  method as usual.)

- version:

  A string specifying the agent CLI version to use. `"auto"` (the
  default) uses a version already installed in the sandbox, falling back
  to the current stable (Claude Code) or latest (Codex) release. Pass a
  specific version (e.g. `"2.1.37"`) for reproducibility.

- sandbox:

  The Inspect sandbox in which the agent runs: a string naming the
  sandbox type, or a length-2 vector pairing a type with a configuration
  file, e.g. `c("docker", "compose.yaml")`. Defaults to `"docker"`,
  which is required on macOS and Windows; on Linux hosts, `"local"` runs
  the agent directly on the host.

## Value

A solver function that can be passed directly to the `solver` argument
of [Task](https://vitals.tidyverse.org/dev/reference/Task.md)'s `$new()`
method. Since the agent runs in a sandbox rather than through ellmer,
the solver's `solver_chat` output contains copies of `solver_chat` whose
turns come from the agent's transcript. Each sample's `solver_metadata`
records the path to the intermediate Inspect log, the sample's token
usage by model, and the agent's error message (if any).

Token usage is recorded in the task's log and in `solver_metadata`, but
not in [Task](https://vitals.tidyverse.org/dev/reference/Task.md)'s
`$token_usage()` method, which only reflects API calls made through
ellmer in the current R session.

## Requirements

These solvers require the reticulate package and a running Docker daemon
([Docker Desktop](https://www.docker.com/products/docker-desktop/) or
similar). Python dependencies are resolved automatically with
[`reticulate::py_require()`](https://rstudio.github.io/reticulate/reference/py_require.html).
The first evaluation additionally pulls the sandbox image and downloads
the agent's command line interface into it, so it takes a few minutes
longer than the ones that follow.

## The agent's workspace

Each sample gets its own container, discarded when the sample completes,
so the agent's edits never touch your machine and never leak from one
sample to the next. The agent starts in its image's working directory,
falling back to the sandbox user's home directory when the image sets
none; pass `cwd` to place it somewhere else.

By default that image is Inspect's own, which contains little more than
a Python installation. To give the agent a repository to work in, or any
other starting state, put a `Dockerfile` or `compose.yaml` in your
working directory and Inspect will build the sandbox from it, or point
`sandbox` at one directly:

    claude_code(
      chat_anthropic(model = "claude-sonnet-4-5"),
      sandbox = c("docker", "path/to/compose.yaml")
    )

See Inspect's [sandboxing
documentation](https://inspect.aisi.org.uk/sandboxing.html) for the
configuration these files support.

## Examples

``` r
if (FALSE) {
  library(tibble)
  library(ellmer)

  simple_addition <- tibble(
    input = c("What's 2+2?", "What's 2+3?"),
    target = c("4", "5")
  )

  tsk <- Task$new(
    dataset = simple_addition,
    solver = claude_code(chat_anthropic(model = "claude-sonnet-4-5")),
    scorer = detect_includes()
  )

  tsk$eval()
}
```
