new_eval_sample <- function(dir = "inst/tre") {
  ui <- shiny::fluidPage(
    shiny::titlePanel("Eval Sample Creator"),
    shiny::fluidRow(
      shiny::column(6,
        shiny::textInput(
          "title",
          "Title",
          width = "100%",
          placeholder = "Just a few words, e.g. 'quarto-inline-backtick'."
        ),
        shiny::textAreaInput(
          "input",
          "Input",
          rows = 12,
          width = "100%",
          placeholder = "A request that a user could make of an LLM. This should be something that's quite hard for e.g. an instance of `ellmer::chat_anthropic()` with no system prompt."
        ),
        shiny::textAreaInput(
          "target",
          "Target",
          placeholder = "Either the desired output or criterion for evaluating the result.",
          width = "100%",
          rows = 7
        )
      ),
      shiny::column(4,
        shiny::selectInput("domain", "Domain",
          choices = c("Data analysis", "Programming", "Authoring")
        ),
        shiny::selectInput("task", "Task",
          choices = c("New code", "Debugging", "Translation")
        ),
        shiny::checkboxGroupInput("knowledge", "Knowledge",
          choices = c("base R", "tidyverse", "shiny", "r-lib", "quarto")
        ),
        shiny::textInput(
          "source",
          "Source URL",
          placeholder = "https://example.com"
        ),
        shiny::actionButton("submit", "Submit")
      )
    )
  )

  server <- function(input, output, session) {
    shiny::observeEvent(input$submit, {
      eval_data <- list(
        title = input$title,
        input = input$input,
        target = input$target,
        domain = input$domain,
        task = input$task,
        source = if(nchar(input$source) > 0) input$source else NA,
        knowledge = input$knowledge
      )

      if (!dir.exists(dir)) {
        dir.create(dir, recursive = TRUE)
      }

      filename <- file.path(dir, paste0(input$title, ".json"))
      jsonlite::write_json(eval_data, filename, auto_unbox = TRUE)

      shiny::showNotification(
        paste("Eval", input$title, "written!"),
        type = "message"
      )

      shiny::updateTextInput(session, "title", value = "")
      shiny::updateTextAreaInput(session, "input", value = "")
      shiny::updateTextAreaInput(session, "target", value = "")
      shiny::updateSelectInput(session, "domain", selected = "Interactive data analysis")
      shiny::updateSelectInput(session, "task", selected = "Debugging")
      shiny::updateTextInput(session, "source", value = "")
      shiny::updateCheckboxGroupInput(session, "knowledge", selected = character(0))
    })
  }

  shiny::shinyApp(ui, server, options = list(launch.browser = TRUE))
}


edit_eval_sample <- function(json_path) {
  data <- jsonlite::read_json(json_path)
  dir <- dirname(json_path)

  ui <- shiny::fluidPage(
    shiny::titlePanel("Eval Sample Editor"),
    shiny::fluidRow(
      shiny::column(6,
        shiny::textInput(
          "title",
          "Title",
          value = data$title,
          width = "100%",
          placeholder = "Just a few words, e.g. 'quarto-inline-backtick'."
        ),
        shiny::textAreaInput(
          "input",
          "Input",
          value = data$input,
          rows = 12,
          width = "100%",
          placeholder = "A request that a user could make of an LLM. This should be something that's quite hard for e.g. an instance of `ellmer::chat_anthropic(model = "claude-sonnet-4-5-20250929")` with no system prompt."
        ),
        shiny::textAreaInput(
          "target",
          "Target",
          value = data$target,
          placeholder = "Either the desired output or criterion for evaluating the result.",
          width = "100%",
          rows = 7
        )
      ),
      shiny::column(4,
        shiny::selectInput("domain", "Domain",
          choices = c("Data analysis", "Programming", "Authoring"),
          selected = data$domain
        ),
        shiny::selectInput("task", "Task",
          choices = c("New code", "Debugging", "Translation"),
          selected = data$task
        ),
        shiny::checkboxGroupInput("knowledge", "Knowledge",
          choices = c("base R", "tidyverse", "shiny", "r-lib", "quarto"),
          selected = data$knowledge
        ),
        shiny::textInput(
          "source",
          "Source URL",
          value = if(is.na(data$source)) "" else data$source,
          placeholder = "https://example.com"
        ),
        shiny::actionButton("submit", "Update")
      )
    )
  )

  server <- function(input, output, session) {
    shiny::observeEvent(input$submit, {
      eval_data <- list(
        title = input$title,
        input = input$input,
        target = input$target,
        domain = input$domain,
        task = input$task,
        source = if(nchar(input$source) > 0) input$source else NA,
        knowledge = input$knowledge
      )

      jsonlite::write_json(eval_data, json_path, auto_unbox = TRUE)

      shiny::showNotification(
        paste("Eval", input$title, "updated!"),
        type = "message"
      )
    })
  }

  shiny::shinyApp(ui, server, options = list(launch.browser = TRUE))
}
