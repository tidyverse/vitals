# Changelog

## vitals (development version)

- [`vitals_view()`](https://vitals.tidyverse.org/dev/reference/vitals_view.md)
  now reads only the leading bytes of each log file when generating the
  homepage; listing a directory of large logs is roughly 250x faster.

- `$log()` now records its fallback temporary directory on the task and
  reports the path it wrote to when no `VITALS_LOG_DIR` is set, so the
  automatic `$view()` succeeds.

- [`detect_pattern()`](https://vitals.tidyverse.org/dev/reference/scorer_detect.md)
  now supports `case_sensitive = TRUE` on R 4.5 and later.

- `Task$new()` now assigns a valid task name when given an inline
  (unnamed) `dataset`, so `$log()` succeeds.

- New
  [`vitals_log_read()`](https://vitals.tidyverse.org/dev/reference/vitals_log_read.md)
  reads an eval log file back into a tibble of samples, reconstructing
  solver (and, for model-graded scorers, scorer) chats as ellmer Chat
  objects.

- Eval logs are substantially more faithful to their source chats.
  Reasoning content, standardized stop reasons, per-turn cached token
  counts, tool parameter schemas, and structured tool errors are now
  written to the log rather than dropped or approximated, and model
  strings follow Inspect’s `provider/model` convention. Remote image
  URLs are logged as-is instead of being downloaded and inlined as data
  URIs.

- Eval log files are dramatically smaller (roughly 4x for multi-turn,
  tool-heavy evals). Repeated content in a sample’s events and base64
  images in its messages are now de-duplicated into the sample’s
  `attachments` pool, mirroring Python Inspect’s behavior.

- The log viewer will now appropriately display tool calls called in
  parallel.

- The log viewer serves log files as-is rather than parsing and
  re-serializing them, making opening a log effectively instant
  (previously several seconds for logs tens of MBs in size).

- Fixed an issue where the log viewer could display one log’s metadata
  (task name, model, score) in place of another’s, both in the log
  listing and when clicking into a log
  ([\#208](https://github.com/tidyverse/vitals/issues/208)).

## vitals 0.3.0

CRAN release: 2026-05-15

### New features

- [`generate_structured()`](https://vitals.tidyverse.org/dev/reference/generate_structured.md)
  extracts structured data from model responses via
  [`ellmer::parallel_chat_structured()`](https://ellmer.tidyverse.org/reference/parallel_chat.html),
  analogous to how
  [`generate()`](https://vitals.tidyverse.org/dev/reference/generate.md)
  wraps
  [`parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
  ([\#153](https://github.com/tidyverse/vitals/issues/153)).

- [`model_graded_qa()`](https://vitals.tidyverse.org/dev/reference/scorer_model.md)
  now encourages brevity in its default `instructions`
  ([\#197](https://github.com/tidyverse/vitals/issues/197)). This
  reduces the tendency of model-graded scorers to “talk themselves out
  of” a reasonable score.

### Log viewer

- Updated the vendored Inspect Log Viewer to version 0.3.161
  ([\#194](https://github.com/tidyverse/vitals/issues/194)).

- Task IDs now follow Inspect’s `task_identifier` format
  (`task_name/model/hash`), including the model name and a hash of
  solver/scorer arguments. This ensures evals with different models or
  arguments appear as separate log viewer entries rather than being
  collapsed as “retries.”

- The home page now includes all of the metadata associated with the
  eval.

- Model events in the log no longer hardcode `max_tokens = 4096`. The
  logged value now reflects the provider’s actual setting, and the field
  is omitted when unset
  ([\#213](https://github.com/tidyverse/vitals/issues/213)).

### Bug fixes

- Accuracy calculation for ordered factor scores with more than two
  levels (e.g. `I < P < C`) no longer inflates partial-credit scores
  when the highest grade is absent from results.

## vitals 0.2.0

CRAN release: 2025-12-01

### New features

- Images, audio, and video in user messages and tool call results will
  now be logged compatibly with the log viewer
  ([\#138](https://github.com/tidyverse/vitals/issues/138),
  [\#171](https://github.com/tidyverse/vitals/issues/171)).

- Solvers and scorers can now return arbitrary R objects in metadata;
  they will be summarized in a lossy format when logged to .json and
  available as-is via `$get_samples()`.

- [`generate()`](https://vitals.tidyverse.org/dev/reference/generate.md)
  now accepts a zero-argument chat factory for `solver_chat`, enabling a
  fresh chat per call instead of cloning an existing chat
  ([\#190](https://github.com/tidyverse/vitals/issues/190)).

- `$eval()` now routes arguments to solvers and scorers based on their
  function signatures, allowing users to pass arguments specific to each
  without requiring ellipses in both functions
  ([\#152](https://github.com/tidyverse/vitals/issues/152)). `$eval()`
  now errors when supplied unnamed arguments.

- Scorers that don’t return `scorer_chat`s can now return an
  `explanation` slot that explains the scoring output. The built-in
  detect-based scorers now return an `explanation` slot
  ([\#189](https://github.com/tidyverse/vitals/issues/189)).

### Viewing logs

- Updated the vendored Inspect Log Viewer to Inspect version 0.3.122,
  bringing all sorts of new features and bug fixes
  ([\#138](https://github.com/tidyverse/vitals/issues/138)).

- Assistant turns now have precise durations in generated logs.
  Previously, their timings were averaged across the course of the
  evaluation ([\#115](https://github.com/tidyverse/vitals/issues/115)).

- The log viewer previously reported the solver’s response as the answer
  provided to the scorer. However, these two texts can differ when
  post-processing of the solver’s response is performed. This is now
  fixed in the log viewer
  ([\#166](https://github.com/tidyverse/vitals/issues/166),
  [\#169](https://github.com/tidyverse/vitals/issues/169) by
  [@mattwarkentin](https://github.com/mattwarkentin)).

- The log viewer previously reported the scorer’s response as both the
  solver’s and scorers response—this is now fixed
  ([\#141](https://github.com/tidyverse/vitals/issues/141),
  [\#142](https://github.com/tidyverse/vitals/issues/142) by
  [@mattwarkentin](https://github.com/mattwarkentin)).

- Tool uses from scorers will now be visible in the log viewer
  ([\#186](https://github.com/tidyverse/vitals/issues/186)).

### Minor improvements and bug fixes

- [`vitals_view()`](https://vitals.tidyverse.org/dev/reference/vitals_view.md)
  will now pick a random available port rather than its previous default
  port, 7576.

- The default `accuracy()` metric will now report a score of 0 rather
  than `NaN` when all scores are 0.

- Fixed bug where non-default grading systems in model-graded evals
  would result in scores being wiped during logging
  ([\#139](https://github.com/tidyverse/vitals/issues/139)).

- The full suite of package tests can now be ran without active API keys
  via the vcr package
  ([\#163](https://github.com/tidyverse/vitals/issues/163)).

- `$eval()` and `$log()` will now write log files to the same default
  directory–the one specified when initializing the Task object.
  Previously, `$eval()` wrote to that directory, while `$log()` wrote to
  [`vitals_log_dir()`](https://vitals.tidyverse.org/dev/reference/vitals_log_dir.md)
  ([\#158](https://github.com/tidyverse/vitals/issues/158) by
  [@SokolovAnatoliy](https://github.com/SokolovAnatoliy)).

- Manifest files for deployed logs are now named `listing.json` rather
  than `logs.json` for compatibility with newer Inspect versions.

- Removed dependency on the rstudioapi package
  ([\#146](https://github.com/tidyverse/vitals/issues/146)).

- The package will now set the envvar `IN_VITALS_EVAL` to `"true"`
  during solving and scoring.

- Numeric task targets will no longer introduce errors in the log
  viewer.

- [`detect_match()`](https://vitals.tidyverse.org/dev/reference/scorer_detect.md)
  now lists the correct `location` options in its default value
  ([\#140](https://github.com/tidyverse/vitals/issues/140),
  [\#142](https://github.com/tidyverse/vitals/issues/142) by
  [@mattwarkentin](https://github.com/mattwarkentin)).

## vitals 0.1.0

CRAN release: 2025-06-24

- Initial CRAN submission.
