# Convert a chat to a solver function with structured output

`generate_structured()` is a variant of
[`generate()`](https://vitals.tidyverse.org/reference/generate.md) that
uses
[`ellmer::parallel_chat_structured()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
to extract structured data from the model's responses. This allows you
to define a schema for the expected output using ellmer's `type_*()`
functions.

Because
[`parallel_chat_structured()`](https://ellmer.tidyverse.org/reference/parallel_chat.html)
returns structured data rather than Chat objects,
`generate_structured()` creates synthetic Chat objects for logging
purposes. These "mock" chats contain the input and JSON-serialized
output as turns, but won't include actual token usage or timing metadata
from the API.

The `result` field contains JSON-serialized strings for compatibility
with existing scorers. The raw structured data is available in
`$get_samples()$solver_metadata` after calling `$solve()` or `$eval()`.

## Usage

``` r
generate_structured(solver_chat = NULL, type = NULL)
```

## Arguments

- solver_chat:

  An ellmer chat object, such as from
  [`ellmer::chat_claude()`](https://ellmer.tidyverse.org/reference/chat_anthropic.html),
  or a zero-argument function that returns one.

- type:

  A type specification for the extracted data, created with ellmer's
  `type_*()` functions (e.g.,
  [`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html),
  [`ellmer::type_string()`](https://ellmer.tidyverse.org/reference/type_boolean.html)).
  This defines the schema for the structured output.

## Value

The output of
[`generate()`](https://vitals.tidyverse.org/reference/generate.md) is
another function. That function takes in a vector of `input`s, as well
as a solver chat by the name of `solver_chat` with the default supplied
to [`generate()`](https://vitals.tidyverse.org/reference/generate.md)
itself.

See the documentation for the `solver` argument in
[Task](https://vitals.tidyverse.org/reference/Task.md) for more
information on the return type.

## See also

[`generate()`](https://vitals.tidyverse.org/reference/generate.md) for
unstructured output,
[`ellmer::type_object()`](https://ellmer.tidyverse.org/reference/type_boolean.html)
and related functions for defining type specifications.

## Examples

``` r
if (FALSE) {
  library(ellmer)

  type_answer <- type_object(
    answer = type_string(
      "The author's first name, with no other formatting."
    )
  )

  names <- tibble::tribble(
    ~input,                                  ~target,
    "Name's Josiah, how's it going?",        "Josiah",
    "I'm Lin, what's your name?",            "Lin",
    "My name is Em Fields, how about you?",  "Em"
  )

  tsk <- Task$new(
    dataset = names,
    solver = generate_structured(
      solver_chat = chat_anthropic(model = "claude-sonnet-4-20250514"),
      type = type_answer
    ),
    scorer = detect_match("any")
  )

  tsk$eval()

  # the result is JSON-serialized for compatibility with scorers
  tsk$get_samples()$result

  # raw structured data is available in solver_metadata
  tsk$get_samples()$solver_metadata

  # solver_chat contains synthetic turns for logging
  tsk$get_samples()$solver_chat[[1]]
}
```
