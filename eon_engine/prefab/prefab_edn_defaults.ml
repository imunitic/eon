open Eon_edn.Edn_effects

let field kvs name =
  match List.assoc_opt (VKeyword name) kvs with
  | Some v -> v
  | None -> failwith (Printf.sprintf "prefab: missing field %S" name)

let field_opt kvs name = List.assoc_opt (VKeyword name) kvs

let as_kvs = function
  | VMap kvs -> kvs
  | _ -> failwith "prefab: expected a map"

let as_string = function VString s -> s | _ -> failwith "prefab: expected a string"
let as_int = function VNumber n -> int_of_float n | _ -> failwith "prefab: expected a number"
let as_bool = function VBool b -> b | _ -> failwith "prefab: expected a boolean"
let as_float = function VNumber n -> n | _ -> failwith "prefab: expected a number"

let as_vec2 = function
  | VVector [ VNumber x; VNumber y ] -> Math.Vec2.create x y
  | _ -> failwith "prefab: expected a [x y] vector"

let as_float_opt = function
  | None -> None
  | Some v -> Some (as_float v)

let as_viewport_opt = function
  | None -> None
  | Some (VVector [ VNumber x; VNumber y; VNumber w; VNumber h ]) -> Some (x, y, w, h)
  | Some _ -> failwith "prefab: expected a [x y w h] viewport vector"

let as_collider_shape = function
  | VMap [ (VKeyword "circle", VNumber r) ] -> Collider.Circle r
  | VMap [ (VKeyword "box", VVector [ VNumber w; VNumber h ]) ] -> Collider.Box (w, h)
  | VMap [ (VKeyword "capsule", VVector [ VNumber r; VNumber h ]) ] -> Collider.Capsule (r, h)
  | _ -> failwith "prefab: unrecognized collider shape"

module Velocity_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v = { Velocity.dx = as_float (field kvs "dx"); dy = as_float (field kvs "dy") } in
    World.set_component world entity Velocity.component v
end

module Local_transform_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v =
      { Local_transform.position = as_vec2 (field kvs "position")
      ; rotation = as_float (field kvs "rotation")
      ; scale = as_vec2 (field kvs "scale")
      }
    in
    World.set_component world entity Local_transform.component v
end

module Collider_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v =
      { Collider.shape = as_collider_shape (field kvs "shape")
      ; layer = as_int (field kvs "layer")
      ; mask = as_int (field kvs "mask")
      ; is_trigger = as_bool (field kvs "is_trigger")
      ; is_static = as_bool (field kvs "is_static")
      }
    in
    World.set_component world entity Collider.component v
end

module Sprite_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v =
      { Sprite.texture_id = as_string (field kvs "texture_id")
      ; layer = as_int (field kvs "layer")
      ; flip_x = as_bool (field kvs "flip_x")
      ; flip_y = as_bool (field kvs "flip_y")
      }
    in
    World.set_component world entity Sprite.component v
end

module Animation_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v =
      { Animation.clip = as_string (field kvs "clip")
      ; frame = as_int (field kvs "frame")
      ; speed = as_float (field kvs "speed")
      ; playing = as_bool (field kvs "playing")
      }
    in
    World.set_component world entity Animation.component v
end

module Camera_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v =
      { Camera.zoom = as_float_opt (field_opt kvs "zoom")
      ; rotation = as_float_opt (field_opt kvs "rotation")
      ; viewport = as_viewport_opt (field_opt kvs "viewport")
      }
    in
    World.set_component world entity Camera.component v
end

module Tag_deserializer = struct
  type raw_data = value

  let deserialize world entity ~key:_ data =
    let kvs = as_kvs data in
    let v = { Tag.value = as_string (field kvs "value") } in
    World.set_component world entity Tag.component v
end

let register_all register_component =
  register_component Velocity.name
    (module Velocity_deserializer : Prefab.Component_deserializer with type raw_data = value);
  register_component Local_transform.name
    (module Local_transform_deserializer : Prefab.Component_deserializer with type raw_data = value);
  register_component Collider.name
    (module Collider_deserializer : Prefab.Component_deserializer with type raw_data = value);
  register_component Sprite.name
    (module Sprite_deserializer : Prefab.Component_deserializer with type raw_data = value);
  register_component Animation.name
    (module Animation_deserializer : Prefab.Component_deserializer with type raw_data = value);
  register_component Camera.name
    (module Camera_deserializer : Prefab.Component_deserializer with type raw_data = value);
  register_component Tag.name
    (module Tag_deserializer : Prefab.Component_deserializer with type raw_data = value)
