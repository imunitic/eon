(* Forces every book example module to link and run its self-checking
   [let () = ...] block, then reports success. This file is NOT part
   of the book itself — it exists purely so `just build`'s "compiles"
   guarantee can be upgraded to "compiles and every assertion in it
   actually passed," for this one verification pass. Run via
   `dune exec eon_engine/examples/book/run_book_examples.exe`.

   Modules are added here as each chapter's example is written. *)

let () =
  ignore Eon_engine_book_examples.World_and_components_example.capabilities_example;
  ignore Eon_engine_book_examples.Queries_and_systems_example.query_example;
  ignore Eon_engine_book_examples.Platform_and_loop_example.input_example;
  ignore Eon_engine_book_examples.Math_example.vec2_example;
  ignore Eon_engine_book_examples.Transform_and_lifecycle_example.hierarchy_example;
  ignore Eon_engine_book_examples.Rendering_example.color_example;
  ignore Eon_engine_book_examples.Audio_example.audio_backend_example;
  ignore Eon_engine_book_examples.Prefab_example.load_and_inheritance_example;
  print_endline "All book examples compiled and ran their assertions successfully."
