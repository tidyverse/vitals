# Read an eval log back into ellmer chats

Reconstruct the samples of a logged evaluation, including their
[ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
objects, from an eval log file written by
[Task](https://vitals.tidyverse.org/reference/Task.md)'s `$log()` method
(or by Python Inspect).

Chats are rebuilt from the log's message history: turn contents (text,
reasoning, images, tool calls, and tool results), per-turn token usage,
durations, and finish reasons are all restored. Information that is not
written to the log–most notably provider configuration beyond the model
name and the raw provider responses–cannot be recovered. Tool functions
are not serializable; pass `tools` to re-attach tool definitions by
name.

## Usage

``` r
vitals_log_read(path, solver_chat = NULL, scorer_chat = NULL, tools = list())
```

## Arguments

- path:

  Path to an eval log file, e.g. an element of the output of
  `list.files(vitals_log_dir(), full.names = TRUE)`.

- solver_chat:

  Optional. An
  [ellmer::Chat](https://ellmer.tidyverse.org/reference/Chat.html)
  object to use as the base for reconstructed solver chats. When `NULL`,
  the chat is constructed with
  [`ellmer::chat()`](https://ellmer.tidyverse.org/reference/chat-any.html)
  using the log's model string; supply this argument when the log's
  provider requires additional configuration (e.g. a `base_url`).

- scorer_chat:

  Optional. Analogous to `solver_chat`, for the chats of model-graded
  scorers.

- tools:

  Optional. A named list of
  [`ellmer::tool()`](https://ellmer.tidyverse.org/reference/tool.html)
  definitions to re-register on the reconstructed chats and attach to
  their tool calls.

## Value

A tibble with columns `id`, `epoch`, `input`, `target`, `result`,
`score`, and `solver_chat`, mirroring the output of
[Task](https://vitals.tidyverse.org/reference/Task.md)'s
`$get_samples()` method. When the log contains model-graded scoring
events, a `scorer_chat` column is included as well.

## Examples

``` r
logs <- list.files(
  system.file("test/inspect/logs", package = "vitals"),
  full.names = TRUE
)

samples <- vitals_log_read(logs[1])

samples$solver_chat[[1]]
#> <Chat Anthropic/claude-3-5-sonnet-latest turns=2 input=14 output=9>
#> ── user ───────────────────────────────────────────────────────────────
#> What's 2+2?
#> ── assistant [input=14 output=9] ──────────────────────────────────────
#> 2+2=4
```
