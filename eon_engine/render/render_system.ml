module Make_with_system
    (B   : Rendering_backend.S)
    (Sys : System.DISPATCH) = struct
  let make ~render_stream_collector =
    let stream = Render_stream.create () in
    Sys.make (System.Exclusive (fun world _dt ->
      Render_stream.clear stream;
      Render_stream_collector.collect render_stream_collector (World.as_ro world) stream;
      Render_stream.store world stream
    ))
end

module Make (B : Rendering_backend.S) = Make_with_system(B)(System.Default)
