(* Companion example for docs/eon_engine chapter: Prefab loading. *)

open Eon_engine

(* Prefab_edn is a functor of a root directory — same shape as
   Asset_lookup.Dir's parameter — instantiate it once with wherever your
   prefab .edn files live. There is no top-level Prefab_edn.load; the
   functor must be applied first. *)
module Prefab_edn = Eon_engine.Prefab_edn.Make (struct
  let path = "eon_engine/examples/book/prefab_assets"
end)

module Health = struct
  type t = { current : int; max : int; regen_rate : float }
  let component : t Eon_engine.Components.t = Eon_engine.component "Health"
end

module Health_deserializer = struct
  open Eon_edn.Edn_effects

  type raw_data = value

  let field kvs name =
    match List.assoc_opt (VKeyword name) kvs with
    | Some v -> v
    | None -> failwith (Printf.sprintf "Health: missing field %S" name)

  let as_int = function VNumber n -> int_of_float n | _ -> failwith "Health: expected a number"
  let as_float = function VNumber n -> n | _ -> failwith "Health: expected a number"

  let deserialize world entity ~key:_ data =
    match data with
    | VMap kvs ->
        let v =
          { Health.current = as_int (field kvs "current")
          ; max = as_int (field kvs "max")
          ; regen_rate = as_float (field kvs "regen_rate")
          }
        in
        Eon_engine.World.set_component world entity Health.component v
    | _ -> failwith "Health: expected a map"
end

let register_tag_handler () =
  Eon_edn.Edn_middleware.register_tag_handler "eon/percent" (fun _ v ->
      match v with
      | Eon_edn.Edn_effects.VString s
        when String.length s > 0 && s.[String.length s - 1] = '%' ->
          let n = float_of_string (String.sub s 0 (String.length s - 1)) in
          Eon_edn.Edn_effects.VNumber (n /. 100.0)
      | _ -> failwith "eon/percent: expected a string like \"75%\"")

let setup_world () =
  let world = Eon_engine.World.create () in
  Eon_engine.Components.Engine_components.register_all world;
  ignore (Eon_engine.World.register world Health.component);
  register_tag_handler ();
  Prefab_edn.register_component "Health"
    (module Health_deserializer : Eon_engine.Prefab.Component_deserializer
      with type raw_data = Eon_edn.Edn_effects.value);
  Eon_engine.Prefab_edn_defaults.register_all Prefab_edn.register_component;
  world

let load_and_inheritance_example () =
  let world = setup_world () in
  let captain = Prefab_edn.load world "goblin_captain" in

  (match World.get_component world captain Health.component with
   | Some (h : Health.t) ->
     assert (h.current = 60 && h.max = 60);
     assert (Float.abs (h.regen_rate -. 0.05) < 1e-9)
   | None -> assert false);

  (match World.get_component world captain Components.Tag.component with
   | Some (tag : Components.Tag.t) -> assert (tag.value = "goblin")
   | None -> assert false);

  (match World.get_component world captain Components.Children.component with
   | Some ({ entities = [ banner ] } : Components.Children.t) ->
     (match World.get_component world banner Components.Tag.component with
      | Some (tag : Components.Tag.t) -> assert (tag.value = "banner")
      | None -> assert false)
   | _ -> assert false)

(* Asset_lookup: maps logical string ids to absolute file paths. Backends
   receive a module Asset_lookup.S at init time and walk it once to
   pre-load assets — game code only ever sees the logical id strings
   afterward. *)
let asset_lookup_example () =
  let module Assets = Asset_lookup.Dir (struct
    let path = "eon_engine/examples/book/prefab_assets"
  end) in
  let found = ref [] in
  Assets.iter (fun logical_id _absolute_path -> found := logical_id :: !found);
  assert (List.mem "goblin_base.edn" !found);
  assert (List.mem "goblin_captain.edn" !found);

  let empty = ref 0 in
  Asset_lookup.Null.iter (fun _ _ -> incr empty);
  assert (!empty = 0);

  Asset_lookup.Scripted.set [ ("sounds/hit.wav", "/tmp/hit.wav") ];
  let scripted = ref [] in
  Asset_lookup.Scripted.iter (fun id path -> scripted := (id, path) :: !scripted);
  assert (!scripted = [ ("sounds/hit.wav", "/tmp/hit.wav") ])

(* Building a custom instantiation: EDN isn't the only option. A minimal
   source/document pair with no real inheritance support — the registry,
   load's spawn work-list, and cycle detection come for free from
   Prefab.Make. *)
module My_format = struct
  type t = (string * (string * string) list) list
  (* [(component_key, [(field, value)]) list] — a toy format, not EDN *)
  let read : t -> t = fun t -> t
end

module My_source = struct
  type raw_data = My_format.t
  let store : (string * My_format.t) list ref = ref []
  let load name =
    match List.assoc_opt name !store with
    | Some d -> d
    | None -> failwith (Printf.sprintf "no such prefab: %s" name)
end

module My_document = struct
  type raw_data = My_format.t
  let extends_of (_ : raw_data) = None
  let components_of (doc : raw_data) = List.map (fun (k, _) -> (k, doc)) doc
  let children_of (_ : raw_data) = []
  let merge (_ : raw_data) (override : raw_data) = override
end

module My_prefab = Eon_engine.Prefab.Make (My_source) (My_document)

module My_tag_deserializer = struct
  type raw_data = My_format.t
  let deserialize world entity ~key:_ (data : raw_data) =
    match List.assoc_opt "Tag" data with
    | Some fields ->
      let value = List.assoc "value" fields in
      World.set_component world entity Components.Tag.component ({ value } : Components.Tag.t)
    | None -> ()
end

let custom_instantiation_example () =
  My_source.store := [ ("npc", [ ("Tag", [ ("value", "npc") ]) ]) ];
  My_prefab.register_component "Tag"
    (module My_tag_deserializer : Prefab.Component_deserializer with type raw_data = My_format.t);

  let world = Eon_engine.World.create () in
  Components.Engine_components.register_all world;
  let e = My_prefab.load world "npc" in
  match World.get_component world e Components.Tag.component with
  | Some (tag : Components.Tag.t) -> assert (tag.value = "npc")
  | None -> assert false

let () =
  load_and_inheritance_example ();
  asset_lookup_example ();
  custom_instantiation_example ()
