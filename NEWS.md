# vitals (development version)

* New `generate_structured()` solver uses `ellmer::parallel_chat_structured()`
  to extract structured data from model responses. `generate_structured()` is to
  `parallel_chat_structured()` as `generate()` is to `parallel_chat()` (#153).

* Updated the vendored Inspect Log Viewer to Inspect version 0.3.151
  (released 30 November 2025, #194).

* The log viewer home page will now show full summaries of each eval.

* Updated the default `model_graded_qa(instructions)` to encourage brevity in reasoning (#197).

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
