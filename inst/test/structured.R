reprex::reprex({
  library(vitals)
  library(ellmer)
  library(tidyverse)

  type_answer <- type_object(
    answer = type_string(
      "The author's first name, with no other formatting."
    )
  )

  names <- tribble(
    ~input                                 , ~target  ,
    "Name's Josiah, how's it going?"       , "Josiah" ,
    "I'm Lin, what's your name?"           , "Lin"    ,
    "My name is Em Fields, how about you?" , "Em"
  )

  tsk <-
    Task$new(
      dataset = names,
      solver = generate_structured(
        solver_chat = chat_anthropic(model = "claude-sonnet-4-20250514"),
        type = type_answer
      ),
      scorer = detect_match("any")
    )

  tsk$eval()

  tsk$get_samples()$solver_chat[[1]]
})
