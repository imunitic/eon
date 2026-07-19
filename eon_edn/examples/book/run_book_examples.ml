(* Forces every book example module to link and run its self-checking
   [let () = ...] block, then reports success. This file is NOT part
   of the book itself — it exists purely so `just build`'s "compiles"
   guarantee can be upgraded to "compiles and every assertion in it
   actually passed," for this one verification pass. Run via
   `dune exec eon_edn/examples/book/run_book_examples.exe`. *)

let () =
  ignore Eon_edn_book_examples.Reading_example.quick_start;
  ignore Eon_edn_book_examples.Middleware_example.config_worked_example;
  print_endline "All book examples compiled and ran their assertions successfully."
