open Alcotest

module Component = Eon_ecs__Component
module Entity_id = Eon_ecs__Entity_id

let e0 = Entity_id.make 0 0
let e1 = Entity_id.make 1 0

let test_make () =
  let c = Component.make 3 "Position" in
  check int "id" 3 c.Component.id;
  check string "name" "Position" c.Component.name

let test_name () =
  let comp = Component.Component (Component.make 5 "Velocity") in
  check string "name" "Velocity" (Component.name comp)

let test_id () =
  let comp = Component.Component (Component.make 7 "Health") in
  check int "id" 7 (Component.id comp)

let test_with_data_mutates_underlying_sparse_set () =
  let comp = Component.Component (Component.make 0 "Tag") in
  Component.with_data comp (fun (data : string Eon_ecs__Sparse_set.t) ->
      Eon_ecs__Sparse_set.add data e0 "hello");
  let found =
    Component.with_data_result comp (fun (data : string Eon_ecs__Sparse_set.t) ->
        Eon_ecs__Sparse_set.get data e0)
  in
  check (option string) "mutation observed through a later with_data call" (Some "hello") found

(* [with_data]'s callback is typed to return [unit] ([Sparse_set.t -> unit]),
   so "ignoring the result" is enforced at the type level, not something
   observable at runtime — this just confirms the call itself is a plain
   side-effecting invocation, distinct from [with_data_result] below. *)
let test_with_data_runs_the_callback () =
  let comp = Component.Component (Component.make 0 "Marker") in
  let ran = ref false in
  Component.with_data comp (fun (_data : unit Eon_ecs__Sparse_set.t) -> ran := true);
  check bool "callback executed" true !ran

let test_with_data_result_returns_callback_result () =
  let comp = Component.Component (Component.make 0 "Counter") in
  Component.with_data comp (fun (data : int Eon_ecs__Sparse_set.t) ->
      Eon_ecs__Sparse_set.add data e0 1;
      Eon_ecs__Sparse_set.add data e1 2);
  let size =
    Component.with_data_result comp (fun (data : int Eon_ecs__Sparse_set.t) ->
        Eon_ecs__Sparse_set.size data)
  in
  check int "with_data_result returns whatever the callback computed" 2 size

let tests =
  [
    test_case "make" `Quick test_make;
    test_case "name" `Quick test_name;
    test_case "id" `Quick test_id;
    test_case "with_data mutates the underlying sparse set" `Quick
      test_with_data_mutates_underlying_sparse_set;
    test_case "with_data runs the callback" `Quick test_with_data_runs_the_callback;
    test_case "with_data_result returns the callback's result" `Quick
      test_with_data_result_returns_callback_result;
  ]
