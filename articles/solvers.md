# Custom solvers and tool calling

In the “Getting started with vitals” vignette, we introduced evaluation
`Task`s with a basic analysis on “An R Eval.” Using the built-in solver
[`generate()`](https://vitals.tidyverse.org/reference/generate.md), we
passed inputs to models and treated their raw responses as the final
result. vitals supports supplying arbitrary functions as solvers,
though. In this example, we’ll use a custom solver to explore the
following question:

> Does equipping models with the ability to peruse package documentation
> make them better at writing R code?

We’ll briefly reintroduce the `are` dataset, define the custom solver,
and then see whether Claude does any better on the `are` Task using the
custom solver compared to plain
[`generate()`](https://vitals.tidyverse.org/reference/generate.md).

First, loading the required packages:

``` r

library(vitals)
library(ellmer)
library(btw)

library(dplyr)
```

## An R eval dataset

From the `are` docs:

> An R Eval is a dataset of challenging R coding problems. Each `input`
> is a question about R code which could be solved on first-read only by
> human experts and, with a chance to read documentation and run some
> code, by fluent data scientists. Solutions are in `target` and enable
> a fluent data scientist to evaluate whether the solution deserves
> full, partial, or no credit.

``` r

glimpse(are)
```

    #> Rows: 29
    #> Columns: 7
    #> $ id        <chr> "after-stat-bar-heights", "conditional-grouped-summ…
    #> $ input     <chr> "This bar chart shows the count of different cuts o…
    #> $ target    <chr> "Preferably: \n\n```\nggplot(data = diamonds) + \n …
    #> $ domain    <chr> "Data analysis", "Data analysis", "Data analysis", …
    #> $ task      <chr> "New code", "New code", "New code", "Debugging", "N…
    #> $ source    <chr> "https://jrnold.github.io/r4ds-exercise-solutions/d…
    #> $ knowledge <list> "tidyverse", "tidyverse", "tidyverse", "r-lib", "t…

At a high level:

- `id`: A unique identifier for the problem.
- `input`: The question to be answered.
- `target`: The solution, often with a description of notable features
  of a correct solution.
- `domain`, `task`, and `knowledge` are pieces of metadata describing
  the kind of R coding challenge.
- `source`: Where the problem came from, as a URL. Many of these coding
  problems are adapted “from the wild” and include the kinds of context
  usually available to those answering questions.

In the introductory vignette, we just provided the `input`s as-is to an
ellmer chat’s `$chat()` method (via the built-in
[`generate()`](https://vitals.tidyverse.org/reference/generate.md)
solver). In this vignette, we’ll compare those results to an approach
resulting from first giving the models a chance to read relevant R
package documentation.

## Custom solvers

To help us better understand how solvers work, lets look at the
implementation of
[`generate()`](https://vitals.tidyverse.org/reference/generate.md).
[`generate()`](https://vitals.tidyverse.org/reference/generate.md) is a
function factory, meaning that the function itself outputs a function.

``` r

sonnet_3_7 <- chat_claude(model = "claude-3-7-sonnet-latest")
generate(solver_chat = sonnet_3_7$clone())
#> function (inputs, ..., solver_chat = chat) 
#> {
#>     if (is.function(solver_chat)) {
#>         ch <- solver_chat()
#>         check_inherits(ch, "Chat")
#>     }
#>     else {
#>         check_inherits(solver_chat, "Chat")
#>         ch <- solver_chat$clone()
#>     }
#>     res <- ellmer::parallel_chat(ch, as.list(inputs), ...)
#>     list(result = purrr::map_chr(res, function(c) c$last_turn()@text), 
#>         solver_chat = res)
#> }
#> <bytecode: 0x55809b909be0>
#> <environment: 0x55809b90fb08>
```

While, in documentation, I’ve mostly written
“[`generate()`](https://vitals.tidyverse.org/reference/generate.md) just
calls `$chat()`,” there are a couple extra tricks up
[`generate()`](https://vitals.tidyverse.org/reference/generate.md)’s
sleeves:

1.  The chat is first cloned with `$clone()` so that the original chat
    object isn’t modified once vitals calls it.
2.  Rather than `$chat()`,
    [`generate()`](https://vitals.tidyverse.org/reference/generate.md)
    calls
    [`ellmer::parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html).
    This is why
    [`generate()`](https://vitals.tidyverse.org/reference/generate.md)
    takes `inputs`–e.g. the whole `input` column–rather than a single
    `input`.
    [`parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
    will send off all of the requests in parallel (not in the usual R
    sense of multiple R processes, but in the sense of asychronous HTTP
    requests), greatly reducing the amount of time it takes to run
    evaluations.

The function that `generate` outputs takes in a list of `inputs` and
outputs a list with two elements:

- `result` is the final result from the solver. In this case,
  `purrr::map_chr(res, function(c) c$last_turn()@text)` just grabs the
  text from the last assistant run and returns it. `result` is a vector
  of length equal to `inputs`—it should be able to be tacked onto
  `task$get_samples()` as another column.
- `solver_chat` is a list of chats that led to the `result`. This may
  seem redundant with `result`, but is important to supply to vitals so
  that the package can log what happened during the solving process and
  display it in the log viewer.

We will work with a slightly modified version of
[`generate()`](https://vitals.tidyverse.org/reference/generate.md) that
equips models with the ability to peruse R package documentation before
answering. We will do so using the btw package, available on GitHub at
<https://posit-dev.github.io/btw/>. Among other things, btw provides a
function
[`btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html)
that returns a list of tools that can be registered with an ellmer chat.

``` r

ch <- sonnet_3_7$clone()
ch$set_tools(btw_tools(tools = "docs"))
```

    ✔ Registered tool btw_tool_docs_package_help_topics
    ✔ Registered tool btw_tool_docs_help_page
    ✔ Registered tool btw_tool_docs_available_vignettes
    ✔ Registered tool btw_tool_docs_vignette

I can use the chat’s `$chat()` method to interact with it like before.
As an example, after registering btw with a Claude Sonnet 3.7 chat
object, I can ask it about this package, vitals. At the time of writing,
vitals is not on CRAN, and Claude Sonnet 3.7 completed training several
months before I started working on it. Nonetheless, the model is able to
tell me about how custom solvers work:

``` r

ch$chat("How do custom solvers work in vitals?")
```

> I’ll help you find information about custom solvers in the vitals
> package. Let me first check if the vitals package is installed and
> then explore its documentation.
>
> The models lets us know it’s reading a bunch of documentation.\<\>
>
> To create a custom solver, you need to:
>
> 1.  Define a function that:
>     - Takes a vector of inputs as its first argument
>     - Returns a list with two elements:
>       - `result`: A vector of final responses (same length as input)
>       - `solver_chat`: The list of ellmer chat objects used (same
>         length as input)
> 2.  Your custom solver can include additional logic to:
>     - Preprocess inputs before sending to the LLM
>     - Post-process model responses
>     - Implement special handling like multi-turn conversations
>     - Incorporate tools or external knowledge
>     - Add retry mechanisms or fallbacks
>
> Yada yada yada.

Pretty spot-on. But will this capability help the models better answer
questions in R? `are` is built from questions about base R and popular
packages like dplyr and shiny, information about which is presumably
baked into their weights.

The implementation of our custom solver looks almost exactly like
[`generate()`](https://vitals.tidyverse.org/reference/generate.md)s
implementation, except we add a call to
[`btw_tools()`](https://posit-dev.github.io/btw/reference/btw_tools.html)
before calling
[`ellmer::parallel_chat()`](https://ellmer.tidyverse.org/reference/parallel_chat.html).

``` r

btw_solver <- function(inputs, ..., solver_chat) {
  ch <- solver_chat$clone()
  ch$set_tools(btw_tools(tools = "docs"))
  res <- ellmer::parallel_chat(ch, as.list(inputs))
  list(
    result = purrr::map_chr(res, function(c) c$last_turn()@text), 
    solver_chat = res
  )
}
```

This solver is ready to situate in a Task and get solving!

## Running the solver

Situate a custom solver in a dataset in the same way you would with a
built-in one:

``` r

are_btw <- Task$new(
  dataset = are,
  solver = btw_solver,
  scorer = model_graded_qa(partial_credit = TRUE, scorer_chat = sonnet_3_7$clone()),
  name = "An R Eval"
)

are_btw
```

As in the introductory vignette, we supply the `are` dataset and the
built-in scorer
[`model_graded_qa()`](https://vitals.tidyverse.org/reference/scorer_model.md).
Then, we use `$eval()` to evaluate our custom solver, evaluate the
scorer, and then explore a persistent log of the results in the
interactive Inspect log viewer.

``` r

are_btw$eval(solver_chat = sonnet_3_7$clone())
```

Any arguments to solving or scoring functions can be passed directly to
`$eval()`, allowing for quickly evaluating tasks across several
parameterizations. We’ll just use Claude Sonnet 3.7 for now.

``` r

are_btw_data <- vitals_bind(are_btw)

are_btw_data
#> # A tibble: 29 × 4
#>    task    id                          score metadata         
#>    <chr>   <chr>                       <ord> <list>           
#>  1 are_btw after-stat-bar-heights      I     <tibble [1 × 10]>
#>  2 are_btw conditional-grouped-summary C     <tibble [1 × 10]>
#>  3 are_btw correlated-delays-reasoning P     <tibble [1 × 10]>
#>  4 are_btw curl-http-get               C     <tibble [1 × 10]>
#>  5 are_btw dropped-level-legend        I     <tibble [1 × 10]>
#>  6 are_btw filter-multiple-conditions  C     <tibble [1 × 10]>
#>  7 are_btw geocode-req-perform         C     <tibble [1 × 10]>
#>  8 are_btw group-by-summarize-message  C     <tibble [1 × 10]>
#>  9 are_btw grouped-filter-summarize    P     <tibble [1 × 10]>
#> 10 are_btw grouped-geom-line           C     <tibble [1 × 10]>
#> # ℹ 19 more rows
```

Claude answered fully correctly in 16 out of 29 samples, and partially
correctly 7 times. Using the metadata, we can also determine how often
the model looked at at least one help-page before supplying an answer:

``` r

chat_called_a_tool <- function(chat) {
  turns <- chat[[1]]$get_turns()
  any(purrr::map_lgl(turns, turn_called_a_tool))
}

turn_called_a_tool <- function(turn) {
  any(purrr::map_lgl(turn@contents, inherits, "ellmer::ContentToolRequest"))
}

are_btw_data |>
  tidyr::hoist(metadata, "solver_chat") |>
  mutate(called_a_tool = purrr::map_lgl(solver_chat, chat_called_a_tool)) |>
  pull(called_a_tool) |> 
  table()
#> 
#> FALSE  TRUE 
#>     2    27
```

When equipped with the ability to peruse documentation, the model almost
always made use of it. To see the kinds of docs it decided to look at,
click in a few samples in the log viewer for this eval:

  

Did perusing documentation actually help the model write better R code,
though? In order to quantify “better,” we need to also run this
evaluation *without* the model being able to access documentation.

Using the same code from the introductory vignette:

``` r

are_basic <- Task$new(
  dataset = are,
  solver = generate(solver_chat = sonnet_3_7$clone()),
  scorer = model_graded_qa(partial_credit = TRUE, scorer_chat = sonnet_3_7$clone()),
  name = "An R Eval"
)

are_basic$eval()
```

(Note that we also could have used `are_btw$set_solver()` here if we
didn’t want to recreate the task.)

``` r

are_eval_data <- 
  # the argument names will become the entries in `task`
  vitals_bind(btw = are_btw, basic = are_basic) |>
  # and, in this case, different tasks correspond to different solvers
  rename(solver = task)

are_eval_data
#> # A tibble: 58 × 4
#>    solver id                          score metadata         
#>    <chr>  <chr>                       <ord> <list>           
#>  1 btw    after-stat-bar-heights      I     <tibble [1 × 10]>
#>  2 btw    conditional-grouped-summary C     <tibble [1 × 10]>
#>  3 btw    correlated-delays-reasoning P     <tibble [1 × 10]>
#>  4 btw    curl-http-get               C     <tibble [1 × 10]>
#>  5 btw    dropped-level-legend        I     <tibble [1 × 10]>
#>  6 btw    filter-multiple-conditions  C     <tibble [1 × 10]>
#>  7 btw    geocode-req-perform         C     <tibble [1 × 10]>
#>  8 btw    group-by-summarize-message  C     <tibble [1 × 10]>
#>  9 btw    grouped-filter-summarize    P     <tibble [1 × 10]>
#> 10 btw    grouped-geom-line           C     <tibble [1 × 10]>
#> # ℹ 48 more rows
```

Is this difference in performance just a result of noise, though? We can
supply the scores to an ordinal regression model to answer this
question.

``` r

library(ordinal)
#> 
#> Attaching package: 'ordinal'
#> The following object is masked from 'package:dplyr':
#> 
#>     slice

are_mod <- clm(score ~ solver, data = are_eval_data)

are_mod
#> formula: score ~ solver
#> data:    are_eval_data
#> 
#>  link  threshold nobs logLik AIC    niter max.grad cond.H 
#>  logit flexible  58   -54.60 115.20 5(0)  5.49e-13 1.5e+01
#> 
#> Coefficients:
#> solverbtw 
#>   -0.3846 
#> 
#> Threshold coefficients:
#>     I|P     P|C 
#> -1.6589 -0.6189
```

The coefficient for `solver == "btw"` is -0.385, indicating that
allowing the model to peruse documentation tends to be associated with
lower grades. If a 95% confidence interval for this coefficient contains
zero, we can conclude that there is not sufficient evidence to reject
the null hypothesis that the difference between the btw solver and basic
solver’s performance on this eval is zero at the 0.05 significance
level.

``` r

confint(are_mod)
#>               2.5 %    97.5 %
#> solverbtw -1.429136 0.6379013
```

If we had evaluated this model across multiple epochs, the question ID
could become a “nuisance parameter” in a mixed model, e.g. with the
model structure `ordinal::clmm(score ~ model + (1|id), ...)`.

This article demonstrated using a custom solver by modifying the
built-in
[`generate()`](https://vitals.tidyverse.org/reference/generate.md) to
allow models to make tool calls that peruse package documentation. With
vitals, tool calling “just works”; calls to any tool registered with
ellmer will automatically be incorporated into evaluation logs.
