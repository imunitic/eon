module Make (Sys : System.DISPATCH) = struct
  let make ?on_command () =
    let extra = Option.value on_command ~default:(fun _ _ -> ()) in
    Sys.make
      ~on_command:(fun world cmd ->
        extra world cmd;
        match cmd with
        | `Destroy_entity entity ->
          if World.is_alive world entity then World.destroy_entity world entity
        | _ -> ()
      )
      (System.Exclusive (fun _world _dt -> ()))
end

module Default = Make(System.Default)
