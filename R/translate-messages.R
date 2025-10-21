translate_to_messages <- function(chat) {
  turns <- chat$get_turns(include_system_prompt = TRUE)
  model <- chat$get_model()
  purrr::map(turns, translate_to_message, model = model)
}

translate_to_message <- function(turn, model) {
  role <- turn@role
  source <- if (role == "user") "input" else "generate"

  message <- list(id = generate_id())

  if (role == "system") {
    message$content <- turn@text
    message$role <- role
    return(message)
  } else if (role == "user") {
    if (
      length(turn@contents) == 1 &&
        inherits(turn@contents[[1]], "ellmer::ContentToolResult")
    ) {
      tool_result <- turn@contents[[1]]
      message$content <- collapse_tool_result(tool_result)
      message$tool_call_id <- tool_result@request@id
      message$`function` <- tool_result@request@name
      return(message)
    } else {
      message$content <- message_content_from_turn(turn)
      message$source <- source
    }
  } else {
    message$content <- list(list(type = "text", text = turn@text))
    message$source <- source

    tool_requests <- purrr::keep(turn@contents, function(content) {
      inherits(content, "ellmer::ContentToolRequest")
    })

    if (length(tool_requests) > 0) {
      tool_calls <- lapply(tool_requests, function(req) {
        list(
          id = req@id,
          `function` = req@name,
          arguments = req@arguments
        )
      })

      message$tool_calls <- tool_calls
      message$model <- model
    }
  }

  message$role <- role

  message
}

collapse_tool_result <- function(tool_result) {
  if (!is.null(tool_result@error)) {
    return(as.character(tool_result@error))
  }

  value <- tool_result@value
  if (!is.list(value)) {
    value <- list(value)
  }

  content_list <- purrr::map(value, tool_result_value_to_content)

  all_text <- all(purrr::map_lgl(content_list, function(x) x$type == "text"))

  if (all_text) {
    return(paste0(
      purrr::map_chr(content_list, function(x) x$text),
      collapse = "\n"
    ))
  }

  content_list
}

tool_result_value_to_content <- function(x) {
  if (is.atomic(x)) {
    return(list(type = "text", text = paste0(x, collapse = "\n")))
  }

  if (inherits(x, "ellmer::ContentImageInline")) {
    media_type <- x@type %||% "image/png"
    return(list(
      type = "image",
      image = paste0("data:", media_type, ";base64,", x@data)
    ))
  }

  if (inherits(x, "ellmer::ContentText")) {
    return(list(type = "text", text = x@text))
  }

  list(type = "text", text = input_string(tibble::as_tibble(x)))
}

extract_format_from_media_type <- function(media_type, default) {
  parts <- strsplit(media_type, "/")[[1]]
  if (length(parts) == 2) {
    return(parts[2])
  }
  default
}
