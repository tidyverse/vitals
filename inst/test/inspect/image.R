library(tidyverse)
library(ellmer)
library(vitals)
devtools::load_all()
plt <- tibble(
  input = "Please make a ggplot of mpg vs hp in mtcars and tell me what you see.",
  target = "Something like `ggplot(mtcars) + aes(x = hp, y = mpg)"
)

tsk <- Task$new(
  dataset = plt,
  solver = generate(
    solver_chat = chat_anthropic()$register_tool(predictive:::tool_run_r_code)
  ),
  scorer = model_graded_qa(scorer_chat = chat_anthropic())
)

tsk$eval()

# ------------------------------------------------------------------

# ch <- chat_anthropic()$register_tool(predictive:::tool_run_r_code)
# ch$chat(
#   "Please make a ggplot of mpg vs hp in mtcars and tell me what you see.",
#   echo = FALSE
# )
