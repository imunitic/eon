type entity_id = Eon_ecs.Entity_id.t

module type Source = sig
  type raw_data
  val load : string -> raw_data
end

module type Component_deserializer = sig
  type raw_data
  val deserialize : World.rw World.t -> entity_id -> key:string -> raw_data -> unit
end

module type Document_shape = sig
  type raw_data
  val extends_of : raw_data -> string option
  val components_of : raw_data -> (string * raw_data) list
  val children_of : raw_data -> raw_data list
  val merge : raw_data -> raw_data -> raw_data
end

module Make (Source : Source) (Doc : Document_shape with type raw_data = Source.raw_data) =
struct
  let registry
      : (string, (module Component_deserializer with type raw_data = Source.raw_data)) Hashtbl.t
    =
    Hashtbl.create 32

  let register_component name deser = Hashtbl.replace registry name deser

  let resolve name =
    let rec go seen name =
      if List.mem name seen then failwith ("prefab inheritance cycle: " ^ name)
      else
        let doc = Source.load name in
        match Doc.extends_of doc with
        | Some parent -> Doc.merge (go (name :: seen) parent) doc
        | None -> doc
    in
    go [] name

  let spawn_one world doc parent =
    let entity = World.create_entity world in
    (match parent with
     | Some p -> Transform_hierarchy.attach world ~parent:p ~child:entity
     | None -> ());
    List.iter
      (fun (key, data) ->
        match Hashtbl.find_opt registry key with
        | Some (module D : Component_deserializer with type raw_data = Source.raw_data) ->
            D.deserialize world entity ~key data
        | None -> failwith ("no deserializer registered for key " ^ key))
      (Doc.components_of doc);
    entity, Doc.children_of doc

  let load world name =
    let root_doc = resolve name in
    let root_entity, root_children = spawn_one world root_doc None in
    let rec loop = function
      | [] -> ()
      | (doc, parent) :: rest ->
          let entity, children = spawn_one world doc (Some parent) in
          let next = List.fold_right (fun child acc -> (child, entity) :: acc) children rest in
          loop next
    in
    loop (List.fold_right (fun child acc -> (child, root_entity) :: acc) root_children []);
    root_entity
end
