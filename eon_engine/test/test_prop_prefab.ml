open Eon_engine
open Eon_edn.Edn_effects
module Tag = Components.Tag
module Children = Components.Children
(* Edn_document is an internal implementation detail of Prefab_edn, not
   part of eon_engine's public API — accessed here the same way eon_ecs's
   tests reach non-public internals. *)
module Edn_document = Eon_engine__Edn_document

let create_world () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  world

let with_prefab_dir files f =
  let dir = Filename.temp_file "eon_prefab_prop" "" in
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

(* --- Property 1: merge_value semantic idempotence --- *)

(* Extensional equality on Eon_edn.value: VMap is compared as an
   unordered key set (merge changes key order, not content), everything
   else structurally. *)
let rec same_value a b =
  match a, b with
  | VMap kvs1, VMap kvs2 ->
      List.length kvs1 = List.length kvs2
      && List.for_all
           (fun (k, v) ->
             match List.assoc_opt k kvs2 with
             | Some v2 -> same_value v v2
             | None -> false)
           kvs1
  | (VList xs1, VList xs2) | (VVector xs1, VVector xs2) ->
      (try List.for_all2 same_value xs1 xs2 with Invalid_argument _ -> false)
  | _ -> a = b

let gen_ident : string QCheck.Gen.t =
  let open QCheck.Gen in
  let letters = List.init 26 (fun i -> Char.chr (Char.code 'a' + i)) in
  map2
    (fun c cs -> String.make 1 c ^ String.concat "" (List.map (String.make 1) cs))
    (oneof_list letters)
    (list_size (int_bound 4) (oneof_list letters))

(* Bounded-depth VMap trees with distinct keys at each level (so
   [same_value] doesn't need to worry about duplicate-key ambiguity). *)
let rec gen_value depth : value QCheck.Gen.t =
  let open QCheck.Gen in
  let scalar =
    oneof_weighted
      [ 1, map (fun n -> VNumber (float_of_int n)) (int_range (-1000) 1000)
      ; 1, map (fun s -> VString s) gen_ident
      ; 1, map (fun b -> VBool b) bool
      ]
  in
  if depth <= 0 then scalar
  else
    oneof_weighted
      [ 3, scalar
      ; 1,
        map
          (fun kvs ->
            (* dedupe keys, keeping first occurrence, to guarantee no
               duplicate-key ambiguity in the generated map *)
            let seen = Hashtbl.create 8 in
            VMap
              (List.filter
                 (fun (k, _) ->
                   if Hashtbl.mem seen k then false
                   else (Hashtbl.add seen k (); true))
                 kvs))
          (list_size (int_bound 4)
             (pair (map (fun s -> VKeyword s) gen_ident) (gen_value (depth - 1))))
      ]

let arb_value = QCheck.make (gen_value 3)

let prop_merge_idempotent =
  QCheck.Test.make ~name:"merge v v is extensionally equal to v" ~count:300 arb_value (fun v ->
      same_value (Edn_document.merge v v) v)

(* --- Property 2: resolve cycle detection over random chain lengths --- *)

let prop_resolve_cycle =
  QCheck.Test.make ~name:"resolve: acyclic chains terminate, cyclic chains raise" ~count:30
    (QCheck.make QCheck.Gen.(int_range 1 6))
    (fun n ->
      let names = List.init n (fun i -> Printf.sprintf "n%d" i) in
      (* acyclic: n(i) extends n(i+1); last one has no :extends *)
      let acyclic_files =
        List.mapi
          (fun i name ->
            if i = n - 1 then (name, {|{:components {}}|})
            else
              ( name
              , Printf.sprintf {|{:extends "n%d" :components {}}|} (i + 1) ))
          names
      in
      let acyclic_ok =
        with_prefab_dir acyclic_files (fun dir ->
            let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
            let world = create_world () in
            try
              ignore (Prefab_edn.load world (List.hd names));
              true
            with Failure _ -> false)
      in
      (* cyclic: same chain, but the last one extends back to the first *)
      let cyclic_files =
        List.mapi
          (fun i name ->
            let next = (i + 1) mod n in
            (name, Printf.sprintf {|{:extends "n%d" :components {}}|} next))
          names
      in
      let cyclic_raises =
        with_prefab_dir cyclic_files (fun dir ->
            let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
            let world = create_world () in
            try
              ignore (Prefab_edn.load world (List.hd names));
              false
            with Failure _ -> true)
      in
      acyclic_ok && cyclic_raises)

(* --- Property 3: Prefab.load produces the same entity-graph shape as a
   naive recursive reference implementation, for random (bounded
   branching, bounded depth) prefab trees --- *)

type tree = { tag : string; children : tree list }

let rec gen_tree depth : tree QCheck.Gen.t =
  let open QCheck.Gen in
  map2
    (fun tag children -> { tag; children })
    gen_ident
    (if depth <= 0 then return [] else list_size (int_bound 3) (gen_tree (depth - 1)))

let arb_tree = QCheck.make (gen_tree 3)

let rec edn_of_tree (t : tree) =
  Printf.sprintf {|{:components {:Tag {:value "%s"}} :children [%s]}|} t.tag
    (String.concat " " (List.map edn_of_tree t.children))

(* naive recursive reference: no work-list, no Prefab at all, spawns
   directly via World/Transform_hierarchy for the same tree shape *)
let rec spawn_naive world parent (t : tree) =
  let entity = World.create_entity world in
  (match parent with
   | Some p -> Transform_hierarchy.attach world ~parent:p ~child:entity
   | None -> ());
  World.set_component world entity Tag.component ({ value = t.tag } : Tag.t);
  List.iter (fun c -> ignore (spawn_naive world (Some entity) c)) t.children;
  entity

type shape = Node of string * shape list

let rec collect_shape world entity =
  let tag =
    match World.get_component world entity Tag.component with
    | Some ({ value } : Tag.t) -> value
    | None -> failwith "missing tag"
  in
  let children =
    match World.get_component world entity Children.component with
    | Some ({ entities } : Children.t) -> entities
    | None -> []
  in
  Node (tag, List.map (collect_shape world) children)

let prop_spawn_matches_naive_reference =
  QCheck.Test.make ~name:"Prefab.load matches a naive recursive reference" ~count:150 arb_tree
    (fun t ->
      let world1 = create_world () in
      let root1 = spawn_naive world1 None t in
      let shape1 = collect_shape world1 root1 in
      with_prefab_dir [ "root", edn_of_tree t ] (fun dir ->
          let module Prefab_edn = Prefab_edn.Make (struct let path = dir end) in
          Prefab_edn_defaults.register_all Prefab_edn.register_component;
          let world2 = create_world () in
          let root2 = Prefab_edn.load world2 "root" in
          let shape2 = collect_shape world2 root2 in
          shape1 = shape2))

let tests =
  [ QCheck_alcotest.to_alcotest prop_merge_idempotent
  ; QCheck_alcotest.to_alcotest prop_resolve_cycle
  ; QCheck_alcotest.to_alcotest prop_spawn_matches_naive_reference
  ]
