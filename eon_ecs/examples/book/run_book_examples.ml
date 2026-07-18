(* Forces every book example module to link and run its self-checking
   [let () = ...] block, then reports success. This file is NOT part
   of the book itself — it exists purely so `just build`'s "compiles"
   guarantee can be upgraded to "compiles and every assertion in it
   actually passed," for this one verification pass. Run via
   `dune exec eon_ecs/examples/book/run_book_examples.exe`. *)

let () =
  (* Referencing one value per module is enough to force that module's
     own top-level [let () = ...] to execute — OCaml runs a linked
     module's full initialization regardless of which binding is used. *)
  ignore Eon_ecs_book_examples.World_example.entity_lifecycle;
  ignore Eon_ecs_book_examples.Queries_example.iter1_example;
  ignore Eon_ecs_book_examples.Buses_example.signals_same_frame;
  ignore Eon_ecs_book_examples.Systems_example.drive_system_directly;
  ignore Eon_ecs_book_examples.Pipelines_example.run_one_tick;
  ignore Eon_ecs_book_examples.Progress_and_loop_example.variable_mode_example;
  print_endline "All book examples compiled and ran their assertions successfully."
