# vitals (development version)


* The log viewer previously reported the solver's response as the answer provided
  to the scorer. However, these two texts can differ when post-processing of
  the solver's response is performed. This is now fixed in the log 
  viewer (#166, #169 by @mattwarkentin).

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

* `$eval()` now routes arguments to solvers and scorers based on
  their function signatures, allowing users to pass arguments specific to each
  without requiring ellipses in both functions (#152). 
  `$eval()` now errors when supplied unnamed arguments.

* Solvers and scorers can now return arbitrary R objects in metadata; they
  will be summarized in a lossy format when logged to .json.

* The package will now set the envvar `IN_VITALS_EVAL` to `"true"` during 
  solving and scoring.

* Numeric task targets will no longer introduce errors in the log viewer.

* Images, audio, and video generated from tool calls will now be logged 
  compatibly with the log viewer (#138).

* Updated the vendored Inspect Log Viewer to Inspect version 0.3.122 (#138).

* `detect_match()` now lists the correct `location` options in its default 
  value (#140, #142 by @mattwarkentin).

* The log viewer previously reported the scorer's response as both the solver's
  and scorers response—this is now fixed (#141, #142 by @mattwarkentin).

# vitals 0.1.0

* Initial CRAN submission.
