type entity_id = Eon_ecs.Entity_id.t

type reparent = {
  entity     : entity_id;
  new_parent : entity_id option;
}

let rec despawn_recursive world entity ~emit =
  (match World.get_component world entity Children.component with
   | None -> ()
   | Some { Children.entities } ->
     List.iter (fun child -> despawn_recursive world child ~emit) entities);
  emit (`Destroy_entity entity)

let attach world ~parent ~child =
  World.set_component world child Parent.component { Parent.entity = parent };
  let existing =
    match World.get_component world parent Children.component with
    | None -> []
    | Some { Children.entities } -> entities
  in
  World.set_component world parent Children.component
    { Children.entities = child :: existing }
