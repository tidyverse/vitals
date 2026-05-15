# vitals (development version)

## New features

* `generate_structured()` extracts structured data from model responses
  via `ellmer::parallel_chat_structured()`, analogous to how `generate()`
  wraps `parallel_chat()` (#153).

* `model_graded_qa()` now encourages brevity in its default `instructions`
  (#197). This reduces the tendency of model-graded scorers to "talk themselves
  out of" a reasonable score.

## Log viewer

* Updated the vendored Inspect Log Viewer to version 0.3.161 (#194).

* Task IDs now follow Inspect's `task_identifier` format
  (`task_name/model/hash`), including the model name and a hash of
  solver/scorer arguments. This ensures evals with different models or
  arguments appear as separate log viewer entries rather than being
  collapsed as "retries."

* The home page now includes all of the metadata associated with the eval.

* Model events in the log no longer hardcode `max_tokens = 4096`. The
  logged value now reflects the provider's actual setting, and the field
  is omitted when unset (#213).

## Bug fixes

* Accuracy calculation for ordered factor scores with more than two
  levels (e.g. `I < P < C`) no longer inflates partial-credit scores
  when the highest grade is absent from results.

# vitals 0.2.0

## New features

* Images, audio, and video in user messages and tool call results will now be 
  logged compatibly with the log viewer (#138, #171).

* Solvers and scorers can now return arbitrary R objects in metadata; they
  will be summarized in a lossy format when logged to .json and available
  as-is via `$get_samples()`.

* `generate()` now accepts a zero-argument chat factory for `solver_chat`,
  enabling a fresh chat per call instead of cloning an existing chat (#190).

* `$eval()` now routes arguments to solvers and scorers based on
  their function signatures, allowing users to pass arguments specific to each
  without requiring ellipses in both functions (#152).
  `$eval()` now errors when supplied unnamed arguments.

* Scorers that don't return `scorer_chat`s can now return an `explanation` slot 
  that explains the scoring output. The built-in detect-based scorers now return 
  an `explanation` slot (#189).

## Viewing logs

* Updated the vendored Inspect Log Viewer to Inspect version 0.3.122, bringing 
  all sorts of new features and bug fixes (#138).

* Assistant turns now have precise durations in generated logs. Previously, 
  their timings were averaged across the course of the evaluation (#115).

* The log viewer previously reported the solver's response as the answer provided
  to the scorer. However, these two texts can differ when post-processing of
  the solver's response is performed. This is now fixed in the log
  viewer (#166, #169 by @mattwarkentin).

* The log viewer previously reported the scorer's response as both the solver's
  and scorers response—this is now fixed (#141, #142 by @mattwarkentin).

* Tool uses from scorers will now be visible in the log viewer (#186).

## Minor improvements and bug fixes

* `vitals_view()` will now pick a random available port rather than its previous default port, 7576.

* The default `accuracy()` metric will now report a score of 0 rather than
  `NaN` when all scores are 0.

* Fixed bug where non-default grading systems in model-graded evals would
  result in scores being wiped during logging (#139).

* The full suite of package tests can now be ran without active API keys via
  the vcr package (#163).

* `$eval()` and `$log()` will now write log files to the same default
  directory--the one specified when initializing the Task object.
  Previously, `$eval()` wrote to that directory, while `$log()` wrote
  to `vitals_log_dir()` (#158 by @SokolovAnatoliy).

* Manifest files for deployed logs are now named `listing.json` rather than `logs.json` for compatibility with newer Inspect versions.

* Removed dependency on the rstudioapi package (#146).

* The package will now set the envvar `IN_VITALS_EVAL` to `"true"` during
  solving and scoring.

* Numeric task targets will no longer introduce errors in the log viewer.

* `detect_match()` now lists the correct `location` options in its default
  value (#140, #142 by @mattwarkentin).

# vitals 0.1.0

* Initial CRAN submission.
