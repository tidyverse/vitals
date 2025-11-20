library(ellmer)
devtools::load_all()

vitals_log_dir_set("image_test")

dataset <- data.frame(
  input = "What does this image show?",
  target = "The image shows a bike."
)

image_solver <- function(inputs, solver_chat = chat_claude()) {
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

log <- list.files("image_test", full.names = TRUE)
expect_valid_log(log)
unlink("image_test", recursive = TRUE)
