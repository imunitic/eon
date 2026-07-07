module Make (Sys : System.DISPATCH) = struct
  module Q = Query.Make(Sparse_set_backend.Default)

  let compose (parent : World_transform.t) (child : Local_transform.t) : World_transform.t = {
    position = Math.Vec2.add parent.position
                 (Math.Vec2.rotate
                   (Math.Vec2.mul_v parent.scale child.position)
                   parent.rotation);
    rotation = parent.rotation +. child.rotation;
    scale    = Math.Vec2.mul_v parent.scale child.scale;
  }

  let propagate world root_entity (root_wt : World_transform.t) =
    let rec loop = function
      | [] -> ()
      | (entity, parent_wt) :: rest ->
        let next = match World.get_component world entity Children.component with
          | None -> rest
          | Some { Children.entities } ->
            List.fold_left (fun acc child ->
              match World.get_component world child Local_transform.component with
              | None -> acc
              | Some lt ->
                let wt = compose parent_wt lt in
                World.set_component world child World_transform.component wt;
                (child, wt) :: acc
            ) rest entities
        in
        loop next
    in
    loop [(root_entity, root_wt)]

  let handle_reparent world entity new_parent =
    (match World.get_component world entity Parent.component with
     | None -> ()
     | Some { Parent.entity = old_parent } ->
       (match World.get_component world old_parent Children.component with
        | None -> ()
        | Some { Children.entities } ->
          let remaining = List.filter (fun e -> e <> entity) entities in
          if remaining = [] then
            World.remove_component world old_parent Children.component
          else
            World.set_component world old_parent Children.component
              { Children.entities = remaining }
       )
    );
    (match new_parent with
     | None ->
       (match World.get_component world entity Parent.component with
        | None -> ()
        | Some _ -> World.remove_component world entity Parent.component)
     | Some p ->
       World.set_component world entity Parent.component { Parent.entity = p }
    );
    match new_parent with
    | None -> ()
    | Some p ->
      (match World.get_component world p Children.component with
       | None ->
         World.set_component world p Children.component { Children.entities = [entity] }
       | Some { Children.entities } ->
         World.set_component world p Children.component
           { Children.entities = entity :: entities }
      )

  let handle_destroy world entity =
    match World.get_component world entity Children.component with
    | None -> ()
    | Some { Children.entities } ->
      List.iter (fun child ->
        World.remove_component world child Parent.component
      ) entities;
      World.remove_component world entity Children.component

  let make () =
    Sys.make
      ~on_command:(fun world cmd ->
        match cmd with
        | `Reparent ({ entity; new_parent } : Hierarchy.reparent) ->
          handle_reparent world entity new_parent
        | `Destroy_entity entity ->
          handle_destroy world entity
        | _ -> ()
      )
      (System.Exclusive (fun world _dt ->
        Q.from world
        |> Q.having Local_transform.name
        |> Q.not_having Parent.name
        |> Q.iter (fun view ->
          let entity = View.entity view in
          let lt = View.get view (module Local_transform) in
          let wt = World_transform.{
            position = lt.position;
            rotation = lt.rotation;
            scale    = lt.scale;
          } in
          World.set_component world entity World_transform.component wt;
          propagate world entity wt
        )
      ))
end

module Default = Make(System.Default)
