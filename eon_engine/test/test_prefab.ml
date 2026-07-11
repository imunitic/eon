open Eon_engine
module Velocity = Components.Velocity
module Tag = Components.Tag
module Children = Components.Children
module Parent = Components.Parent

let create_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

(* Fresh temp directory per test so prefab files don't collide across
   tests running in the same process. *)
let with_prefab_dir files f =
  let dir = Filename.temp_file "eon_prefab_test" "" in
  Sys.remove dir;
  Unix.mkdir dir 0o755;
  List.iter
    (fun (name, contents) ->
      let oc = open_out (Filename.concat dir (name ^ ".edn")) in
      output_string oc contents;
      close_out oc)
    files;
  Fun.protect
    ~finally:(fun () ->
      List.iter (fun (name, _) -> Sys.remove (Filename.concat dir (name ^ ".edn"))) files;
      Unix.rmdir dir)
    (fun () -> f dir)

let test_single_prefab_load () =
  with_prefab_dir
    [ "hero", {|{:components {:Velocity {:dx 1.5 :dy -2.5} :Tag {:value "hero"}}}|} ]
    (fun dir ->
      let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
      Prefab_edn_defaults.register_all Prefab_edn.register_component;
      let world = create_world () in
      let entity = Prefab_edn.load world "hero" in
      let velocity = World.get_component world entity Velocity.component in
      let tag = World.get_component world entity Tag.component in
      Alcotest.(check bool) "velocity set" true
        (velocity = Some ({ dx = 1.5; dy = -2.5 } : Velocity.t));
      Alcotest.(check bool) "tag set" true (tag = Some ({ value = "hero" } : Tag.t)))

let test_inheritance () =
  with_prefab_dir
    [ "goblin_base", {|{:components {:Tag {:value "goblin"} :Velocity {:dx 0 :dy 0}}}|}
    ; "goblin_archer",
      {|{:extends "goblin_base" :components {:Velocity {:dx 5 :dy 0}}}|}
    ]
    (fun dir ->
      let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
      Prefab_edn_defaults.register_all Prefab_edn.register_component;
      let world = create_world () in
      let entity = Prefab_edn.load world "goblin_archer" in
      let velocity = World.get_component world entity Velocity.component in
      let tag = World.get_component world entity Tag.component in
      Alcotest.(check bool) "velocity overridden" true
        (velocity = Some ({ dx = 5.0; dy = 0.0 } : Velocity.t));
      Alcotest.(check bool) "tag inherited" true (tag = Some ({ value = "goblin" } : Tag.t)))

let test_cyclic_extends_raises () =
  with_prefab_dir
    [ "a", {|{:extends "b" :components {}}|}
    ; "b", {|{:extends "a" :components {}}|}
    ]
    (fun dir ->
      let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
      Prefab_edn_defaults.register_all Prefab_edn.register_component;
      let world = create_world () in
      Alcotest.check_raises "cyclic extends raises"
        (Failure "prefab inheritance cycle: a")
        (fun () -> ignore (Prefab_edn.load world "a")))

let test_nested_children () =
  with_prefab_dir
    [ "parent",
      {|{:components {:Tag {:value "parent"}}
         :children [{:components {:Tag {:value "child1"}}}
                     {:components {:Tag {:value "child2"}}}]}|}
    ]
    (fun dir ->
      let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
      Prefab_edn_defaults.register_all Prefab_edn.register_component;
      let world = create_world () in
      let root = Prefab_edn.load world "parent" in
      let children = World.get_component world root Children.component in
      match children with
      | Some ({ entities } : Children.t) ->
          Alcotest.(check int) "two children attached" 2 (List.length entities);
          List.iter
            (fun child ->
              let parent = World.get_component world child Parent.component in
              Alcotest.(check bool) "child's Parent points back to root" true
                (match parent with
                 | Some ({ entity } : Parent.t) -> Eon_ecs.Entity_id.equal entity root
                 | None -> false))
            entities
      | None -> Alcotest.fail "expected Children component on root")

let test_unregistered_component_key_raises () =
  with_prefab_dir [ "bad", {|{:components {:NoSuchKey {:x 1}}}|} ] (fun dir ->
      let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
      (* deliberately don't register any deserializers *)
      let world = create_world () in
      Alcotest.check_raises "unregistered key raises"
        (Failure "no deserializer registered for key NoSuchKey")
        (fun () -> ignore (Prefab_edn.load world "bad")))

let test_deep_nesting_no_stack_overflow () =
  let depth = 50_000 in
  let rec chain n =
    if n = 0 then "{:components {:Tag {:value \"leaf\"}}}"
    else Printf.sprintf {|{:components {:Tag {:value "n%d"}} :children [%s]}|} n (chain (n - 1))
  in
  with_prefab_dir [ "deep", chain depth ] (fun dir ->
      let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
      Prefab_edn_defaults.register_all Prefab_edn.register_component;
      let world = create_world () in
      let root = Prefab_edn.load world "deep" in
      Alcotest.(check bool) "root spawned without stack overflow" true
        (World.is_alive world root))

let tests = [
  Alcotest.test_case "single prefab load" `Quick test_single_prefab_load;
  Alcotest.test_case "inheritance: override + inherit + add" `Quick test_inheritance;
  Alcotest.test_case "cyclic extends raises" `Quick test_cyclic_extends_raises;
  Alcotest.test_case "nested children wired via Transform_hierarchy" `Quick test_nested_children;
  Alcotest.test_case "unregistered component key raises" `Quick test_unregistered_component_key_raises;
  Alcotest.test_case "deep nesting: no stack overflow" `Slow test_deep_nesting_no_stack_overflow;
]
