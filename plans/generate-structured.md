# Implement `generate_structured()`

## Background

Users want to combine structured output (`parallel_chat_structured()`) with vitals evaluations. The problem: `parallel_chat_structured()` returns structured data directly rather than Chat objects, but vitals' logging requires Chat objects with turns to extract messages, model usage, and other metadata.

The solution (from [#153](https://github.com/tidyverse/vitals/issues/153#issuecomment-3372896178)): create `generate_structured()` that:
1. Uses `parallel_chat_structured()` for the actual LLM calls
2. Creates "mock" Chat objects that contain synthetic turns representing the input/output exchange
3. Returns these mock chats as `solver_chat` so logging still works

## Implementation

### Phase 1: Add `generate_structured()` to `R/solver.R`

- [x] Add `generate_structured()` function below `generate()`
- [x] Function signature: `generate_structured(solver_chat = NULL, type = NULL)`
- [x] Returns a solver function with signature `function(inputs, ..., solver_chat = chat, type = type_spec)`
- [x] Solver function:
  1. Clones the chat
  2. Calls `ellmer::parallel_chat_structured(ch, as.list(inputs), type = type, ...)`
  3. Creates mock chats via helper function
  4. Returns `list(result = result_strings, solver_chat = solver_chats, solver_metadata = res_per_input)`

### Phase 2: Add helper functions

- [x] Add `mock_chat()` helper function (not exported)
- [x] Takes: `input`, `result`, `solver_chat`
- [x] Creates a UserTurn with `ContentText(as.character(input))`
- [x] Creates an AssistantTurn with `ContentText()` containing JSON-serialized result
- [x] Uses `chat$set_turns()` to replace turns
- [x] Returns the modified chat clone
- [x] Add `split_structured_result()` helper to handle tibbles vs lists from `parallel_chat_structured()`

### Phase 3: Documentation

- [x] Add roxygen documentation for `generate_structured()`
- [x] Document that the `solver_chat` objects are "mocked" and won't contain full conversation metadata
- [x] Add `@param type` documentation explaining it should be created with `type_*()` functions
- [x] Add `@seealso` reference to `generate()` and ellmer's `type_object()` etc.

### Phase 4: Testing

- [x] Add tests to `tests/testthat/test-solver.R` for `generate_structured()`
- [x] Test that `generate_structured()` returns a function
- [x] Test that the returned function produces correct structure (`result`, `solver_chat`, `solver_metadata`)
- [x] Test that `solver_chat` elements are Chat objects
- [x] Test integration with `Task$new()` and `$eval()` - verify logs pass `expect_valid_log()`

### Phase 5: Export

- [x] Add `@export` to `generate_structured()`
- [x] Run `devtools::document()` to update NAMESPACE

## Key Implementation Changes vs Original Plan

1. **Result conversion**: The `result` field returns JSON-serialized strings (not the raw structured data) for compatibility with existing scorers. Raw structured data is available in `solver_metadata`.

2. **`split_structured_result()`**: Added helper to handle the fact that `parallel_chat_structured()` returns a tibble (when `type` is an object) rather than a list. This splits the tibble by rows for mapping over inputs.

3. **`turn_tokens()` fix**: Updated `R/translate-events.R` to handle `NA` token values (which mock chats have) by converting to `0L` instead of letting them serialize as "NA" strings.

## Considerations

- The mocked chats won't have real token usage data (reports 0 for all token counts)
- The `@duration` slot on turns won't be set, which affects timing metadata in logs
- This is acceptable as documented behavior - users trade metadata completeness for structured output convenience
- The `solver_metadata` field provides access to the raw structured data for users who need it
