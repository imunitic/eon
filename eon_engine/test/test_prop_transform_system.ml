open Eon_engine

(* [Components.Foo] is constrained to [Component.S] (type t, component, name
   only), so field labels aren't in scope through that path — same gap
   ecs-044/ecs-046 found. Reach the raw internal modules directly for
   construction/projection; [Components.Foo.component] is still fine for
   registration since that's exposed by [Component.S]. *)
module Raw_local_transform = Eon_engine__Local_transform
module Raw_world_transform = Eon_engine__World_transform
module Raw_parent = Eon_engine__Parent
module Raw_children = Eon_engine__Children

(* Reference oracle mirroring transform_system.ml's own composition formula
   (position = parent.position + rotate(parent.scale * child.position,
   parent.rotation); rotation = parent.rotation + child.rotation; scale =
   parent.scale * child.scale) — this is the mathematical definition of 2D
   parent/child transform composition, not copied source, so re-deriving it
   here is a legitimate independent check, not a tautology. *)
let expected_compose (parent : Raw_world_transform.t) (child : Raw_local_transform.t) :
    Raw_world_transform.t =
  {
    position =
      Math.Vec2.add parent.position
        (Math.Vec2.rotate (Math.Vec2.mul_v parent.scale child.position) parent.rotation);
    rotation = parent.rotation +. child.rotation;
    scale = Math.Vec2.mul_v parent.scale child.scale;
  }

(* ------------------------------------------------------------------ *)
(* Random tree generation: node 0 is always the root; every later node's *)
(* parent is a strictly-earlier node, so the structure is a tree by      *)
(* construction — no separate cycle-avoidance logic needed.              *)
(* ------------------------------------------------------------------ *)

type node = { local : Raw_local_transform.t; parent : int option }

let gen_local =
  let open QCheck.Gen in
  let gen_float = float_range (-10.0) 10.0 in
  let gen_scale = float_range 0.5 2.0 in
  let* px = gen_float and* py = gen_float in
  let* rotation = float_range (-6.28) 6.28 in
  let* sx = gen_scale and* sy = gen_scale in
  return
    Raw_local_transform.{ position = { Math.Vec2.x = px; y = py }; rotation; scale = { x = sx; y = sy } }

let gen_tree =
  let open QCheck.Gen in
  let* n = int_range 1 25 in
  let* root_local = gen_local in
  let* rest =
    List.init (n - 1) (fun i -> i + 1)
    |> List.fold_left
         (fun acc i ->
           let* acc = acc in
           let* local = gen_local in
           let* parent_idx = int_range 0 (i - 1) in
           return ((i, { local; parent = Some parent_idx }) :: acc))
         (return [])
  in
  return ((0, { local = root_local; parent = None }) :: List.rev rest)

let pp_tree nodes = Printf.sprintf "n=%d" (List.length nodes)

let arb_tree = QCheck.make ~print:pp_tree gen_tree

let children_of nodes parent_idx =
  List.filter_map (fun (i, n) -> if n.parent = Some parent_idx then Some i else None) nodes

let rec expected_world nodes idx =
  let n = List.assoc idx nodes in
  match n.parent with
  | None ->
      Raw_world_transform.{ position = n.local.position; rotation = n.local.rotation; scale = n.local.scale }
  | Some pidx -> expected_compose (expected_world nodes pidx) n.local

let approx_eq eps a b = Float.abs (a -. b) <= eps

let world_transform_eq eps (a : Raw_world_transform.t) (b : Raw_world_transform.t) =
  approx_eq eps a.position.x b.position.x
  && approx_eq eps a.position.y b.position.y
  && approx_eq eps a.rotation b.rotation
  && approx_eq eps a.scale.x b.scale.x
  && approx_eq eps a.scale.y b.scale.y

let prop_world_transform_matches_ancestor_chain_composition =
  let test_fn nodes =
    let world = World.create () in
    Components.Engine_components.register_all world;
    (* First pass: create every entity, keyed by tree index. *)
    let entity_of_index = Array.init (List.length nodes) (fun _ -> World.create_entity world) in
    (* Second pass: wire Local_transform, Parent, Children. *)
    List.iter
      (fun (i, n) ->
        World.set_component world entity_of_index.(i) Components.Local_transform.component n.local;
        match n.parent with
        | None -> ()
        | Some pidx ->
            World.set_component world entity_of_index.(i) Components.Parent.component
              (Raw_parent.{ entity = entity_of_index.(pidx) }))
      nodes;
    List.iter
      (fun (i, _) ->
        match children_of nodes i with
        | [] -> ()
        | kids ->
            World.set_component world entity_of_index.(i) Components.Children.component
              (Raw_children.{ entities = List.map (fun k -> entity_of_index.(k)) kids }))
      nodes;

    let sys = Transform_system.Default.make () in
    let pipe =
      Pipeline.Default.create () |> Pipeline.Default.add_phase `Transform
      |> Pipeline.Default.add_system `Transform sys
    in
    Pipeline.Default.register_all pipe world;
    Fun.protect
      ~finally:(fun () -> Pipeline.Default.reset pipe)
      (fun () ->
        ignore (Pipeline.Default.run pipe world 0.016);
        List.for_all
          (fun (i, _) ->
            match World.get_component world entity_of_index.(i) Components.World_transform.component with
            | None -> false
            | Some actual -> world_transform_eq 1e-6 actual (expected_world nodes i))
          nodes)
  in
  QCheck.Test.make
    ~name:"Transform_system: every node's World_transform equals composing local transforms \
           along its root-to-node path"
    ~count:300 arb_tree test_fn

let tests = [ QCheck_alcotest.to_alcotest prop_world_transform_matches_ancestor_chain_composition ]
