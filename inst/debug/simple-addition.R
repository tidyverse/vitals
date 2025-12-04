library(vitals)

vitals_log_dir_set("inst/debug/vitals/")

simple_addition <- tibble(
  input = c("What's 2+2?", "What's 2+3?", "What's 2+4?"),
  target = c("4", "5", "6")
)

tsk <- Task$new(
  dataset = simple_addition,
  solver = generate(chat_claude(model = "claude-sonnet-4-5")),
  scorer = model_graded_qa()
)

tsk$eval()
