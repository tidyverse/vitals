# vitals_log_read errors informatively

    Code
      vitals_log_read("no-such-file.json")
    Condition
      Error in `vitals_log_read()`:
      ! `path` does not exist: 'no-such-file.json'.

---

    Code
      vitals_log_read(log_path, solver_chat = "not a chat")
    Condition
      Error in `vitals_log_read()`:
      ! `solver_chat` must be a <Chat>, not a string

