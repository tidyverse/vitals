library(ellmer)

dataset <- data.frame(
  input = "What does this image show?",
  target = "The image shows a bike."
)

image_solver <- function(inputs, solver_chat = chat_anthropic()) {
  image_file <- system.file("test/x.png", package = "vitals")

  ch <- solver_chat$clone()
  ch$chat(inputs[1], content_image_file(image_file))

  list(
    result = ch$last_turn()@text,
    solver_chat = list(ch)
  )
}

tsk <- Task$new(
  dataset = dataset,
  solver = image_solver,
  scorer = model_graded_qa()
)

tsk$eval()
