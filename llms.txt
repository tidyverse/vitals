# vitals

vitals is a framework for large language model evaluation in R. It’s
specifically aimed at [ellmer](https://ellmer.tidyverse.org/) users who
want to measure the effectiveness of their LLM products like [custom
chat apps](https://posit.co/blog/custom-chat-app/) and
[querychat](https://github.com/posit-dev/querychat) apps. You can use it
to:

- Measure whether changes in your prompts or additions of new tools
  improve performance in your LLM product
- Compare how different models affect performance, cost, and/or latency
  of your LLM product
- Surface problematic behaviors in your LLM product

The package is an R port of the widely adopted Python framework
[Inspect](https://inspect.ai-safety-institute.org.uk/). While the
package doesn’t integrate with Inspect directly, it allows users to
interface with the [Inspect log
viewer](https://inspect.ai-safety-institute.org.uk/log-viewer.html) and
provides an on-ramp to transition to Inspect if need be by writing
evaluation logs to the same file format.

## Installation

Install the vitals package from CRAN with:

``` r

install.packages("vitals")
```

You can install the developmental version of vitals using:

``` r

pak::pak("tidyverse/vitals")
```

## Example

LLM evaluation with vitals is composed of two main steps.

``` r

library(vitals)
library(ellmer)
library(tibble)
```

1.  First, create an evaluation **task** with the `Task$new()` method.

``` r

simple_addition <- tibble(
  input = c("What's 2+2?", "What's 2+3?", "What's 2+4?"),
  target = c("4", "5", "6")
)

tsk <- Task$new(
  dataset = simple_addition, 
  solver = generate(chat_claude(model = "claude-sonnet-4-5")), 
  scorer = model_graded_qa()
)
```

Tasks are composed of three main components:

- **Datasets** are a data frame with, minimally, columns `input` and
  `target`. `input` represents some question or problem, and `target`
  gives the target response.
- **Solvers** are functions that take `input` and return some value
  approximating `target`, likely wrapping ellmer chats.
  [`generate()`](https://vitals.tidyverse.org/reference/generate.md) is
  the simplest scorer in vitals, and just passes the `input` to the
  chat’s `$chat()` method, returning its result as-is.
- **Scorers** juxtapose the solvers’ output with `target`, evaluating
  how well the solver solved the `input`.

2.  Evaluate the task.

``` r

tsk$eval()
```

`$eval()` will run the solver, run the scorer, and then situate the
results in a persistent log file that can be explored interactively with
the Inspect log viewer.

![A screenshot of the Inspect log viewer, an interactive app displaying
information on the 3 samples evaluated in this
eval.](reference/figures/log_viewer.png)

Any arguments to the solver or scorer can be passed to `$eval()`,
allowing for straightforward parameterization of tasks. For example, if
I wanted to evaluate
[`chat_openai()`](https://ellmer.tidyverse.org/reference/chat_openai.html)
on this task rather than
[`chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
I could write:

``` r

tsk_openai <- tsk$clone()
tsk_openai$eval(solver_chat = chat_openai(model = "gpt-4.1"))
```

For an applied example, see the “Getting started with vitals” vignette
at `vignette("vitals", package = "vitals")`.

# Package index

## Evaluation tasks

- [`Task`](https://vitals.tidyverse.org/reference/Task.md) : Creating
  and evaluating tasks

## Solvers

- [`generate()`](https://vitals.tidyverse.org/reference/generate.md) :
  Convert a chat to a solver function
- [`generate_structured()`](https://vitals.tidyverse.org/reference/generate_structured.md)
  : Convert a chat to a solver function with structured output

## Scorers

- [`model_graded_qa()`](https://vitals.tidyverse.org/reference/scorer_model.md)
  [`model_graded_fact()`](https://vitals.tidyverse.org/reference/scorer_model.md)
  : Model-based scoring
- [`detect_includes()`](https://vitals.tidyverse.org/reference/scorer_detect.md)
  [`detect_match()`](https://vitals.tidyverse.org/reference/scorer_detect.md)
  [`detect_pattern()`](https://vitals.tidyverse.org/reference/scorer_detect.md)
  [`detect_exact()`](https://vitals.tidyverse.org/reference/scorer_detect.md)
  [`detect_answer()`](https://vitals.tidyverse.org/reference/scorer_detect.md)
  : Scoring with string detection

## Store, view, deploy, and compare evaluation logs

- [`vitals_log_dir()`](https://vitals.tidyverse.org/reference/vitals_log_dir.md)
  [`vitals_log_dir_set()`](https://vitals.tidyverse.org/reference/vitals_log_dir.md)
  : The log directory
- [`vitals_view()`](https://vitals.tidyverse.org/reference/vitals_view.md)
  : Interactively view local evaluation logs
- [`vitals_bundle()`](https://vitals.tidyverse.org/reference/vitals_bundle.md)
  : Prepare logs for deployment
- [`vitals_bind()`](https://vitals.tidyverse.org/reference/vitals_bind.md)
  : Concatenate task samples for analysis

## Example Evals

- [`are`](https://vitals.tidyverse.org/reference/are.md) : An R Eval

# Articles

### All vignettes

- [Analyzing evaluation
  results](https://vitals.tidyverse.org/articles/analysis.md):
- [Custom solvers and tool
  calling](https://vitals.tidyverse.org/articles/solvers.md):
- [Getting started with
  vitals](https://vitals.tidyverse.org/articles/vitals.md):
- [Writing evals for your LLM
  product](https://vitals.tidyverse.org/articles/writing-evals.md):
