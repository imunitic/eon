(* Transcribed into doc/middleware.mld — keep in sync by hand. *)

let unregistered_tag_wraps () =
  let v =
    Eon_edn.Edn_middleware.run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  match v with
  | Eon_edn.Edn_effects.VTagged ("uuid", VString "abc") -> ()
  | _ -> assert false

let registered_tag_transforms () =
  Eon_edn.Edn_middleware.register_tag_handler "uuid" (fun _ v ->
      match v with
      | Eon_edn.Edn_effects.VString s ->
          Eon_edn.Edn_effects.VTagged ("uuid", VString (String.uppercase_ascii s))
      | v -> v);
  let v =
    Eon_edn.Edn_middleware.run_with_middleware
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  match v with
  | Eon_edn.Edn_effects.VTagged ("uuid", VString "ABC") -> ()
  | _ -> assert false

let composed_handlers () =
  let v =
    Eon_edn.Edn_middleware.run_with_middleware
      ~handlers:Eon_edn.Edn_middleware.[ log_tags; strict_tags [ "uuid" ] ]
      (fun () -> Eon_edn.Edn_parser.value ())
      {|#uuid "abc"|}
  in
  ignore v

(* --- Worked example: loading a config file into a typed record --- *)

open Eon_edn.Edn_effects

let field kvs name =
  match List.assoc_opt (VKeyword name) kvs with
  | Some v -> v
  | None -> failwith (Printf.sprintf "config: missing field %S" name)

let as_string = function VString s -> s | _ -> failwith "config: expected a string"
let as_int = function VNumber n -> int_of_float n | _ -> failwith "config: expected a number"
let as_bool = function VBool b -> b | _ -> failwith "config: expected a boolean"
let as_float = function VNumber n -> n | _ -> failwith "config: expected a number"

type config = {
  name : string;
  width : int;
  height : int;
  fullscreen : bool;
  volume : float;
}

let config_of_value = function
  | VMap kvs ->
      { name = as_string (field kvs "name")
      ; width = as_int (field kvs "width")
      ; height = as_int (field kvs "height")
      ; fullscreen = as_bool (field kvs "fullscreen")
      ; volume = as_float (field kvs "volume")
      }
  | _ -> failwith "config: expected a top-level map"

let load_config_string contents =
  Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value contents |> config_of_value

let config_worked_example () =
  let cfg =
    load_config_string
      {|{:name "My Game" :width 1920 :height 1080 :fullscreen false :volume 0.8}|}
  in
  assert (cfg.name = "My Game");
  assert (cfg.width = 1920);
  assert (cfg.height = 1080);
  assert (cfg.fullscreen = false);
  assert (cfg.volume = 0.8)

(* --- Worked example: nested maps, vectors of maps, and lists of
   mixed-typed scalars — a small level save file --- *)

let as_vector = function
  | VVector l -> l
  | _ -> failwith "level: expected a vector"

let as_string_list v = List.map as_string (as_vector v)

type item = { item_name : string; damage : int; equipped : bool }

let item_of_value = function
  | VMap kvs ->
      { item_name = as_string (field kvs "item")
      ; damage = as_int (field kvs "damage")
      ; equipped = as_bool (field kvs "equipped")
      }
  | _ -> failwith "item: expected a map"

type entity = {
  entity_name : string;
  position : float * float;
  tags : string list;
  inventory : item list;
}

let position_of_value = function
  | VVector [ VNumber x; VNumber y ] -> (x, y)
  | _ -> failwith "entity: expected a 2-element position vector"

let entity_of_value = function
  | VMap kvs ->
      { entity_name = as_string (field kvs "name")
      ; position = position_of_value (field kvs "position")
      ; tags = as_string_list (field kvs "tags")
      ; inventory = List.map item_of_value (as_vector (field kvs "inventory"))
      }
  | _ -> failwith "entity: expected a map"

type level = { level_name : string; entities : entity list }

let level_of_value = function
  | VMap kvs ->
      { level_name = as_string (field kvs "level")
      ; entities = List.map entity_of_value (as_vector (field kvs "entities"))
      }
  | _ -> failwith "level: expected a top-level map"

let load_level_string contents =
  Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value contents |> level_of_value

let level_worked_example () =
  let lvl =
    load_level_string
      {|{:level "Forest Ruins"
         :entities [{:name "Player"
                     :position [3.5 -1.2]
                     :tags ["hero" "controllable"]
                     :inventory [{:item "Sword" :damage 12 :equipped true}
                                 {:item "Potion" :damage 0 :equipped false} ] }
                    {:name "Goblin"
                     :position [10.0 4.0]
                     :tags []
                     :inventory [] } ] }|}
  in
  assert (lvl.level_name = "Forest Ruins");
  match lvl.entities with
  | [ player; goblin ] ->
      assert (player.entity_name = "Player");
      assert (player.position = (3.5, -1.2));
      assert (player.tags = [ "hero"; "controllable" ]);
      (match player.inventory with
       | [ sword; potion ] ->
           assert (sword.item_name = "Sword" && sword.damage = 12 && sword.equipped);
           assert (potion.item_name = "Potion" && potion.damage = 0 && not potion.equipped)
       | _ -> assert false);
      assert (goblin.entity_name = "Goblin");
      assert (goblin.position = (10.0, 4.0));
      assert (goblin.tags = []);
      assert (goblin.inventory = [])
  | _ -> assert false

let () =
  unregistered_tag_wraps ();
  registered_tag_transforms ();
  composed_handlers ();
  config_worked_example ();
  level_worked_example ()
