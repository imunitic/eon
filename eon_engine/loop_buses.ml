type world = Eon_ecs.World.t

let require_service world name =
  match Eon_ecs.World.get_service world name with
  | Some service -> service
  | None ->
    failwith (Printf.sprintf "Loop_buses: missing service (hash:%d)"
                (Hashtbl.hash name land Stdlib.max_int))

let collect world =
  let signals  : _ Single_bus.t = require_service world `Signals  in
  let events   : _ Double_bus.t = require_service world `Events   in
  let commands : _ Single_bus.t = require_service world `Commands in
  Single_bus.collect signals;
  Double_bus.collect events;
  Single_bus.collect commands

let drain world =
  let signals  : _ Single_bus.t = require_service world `Signals  in
  let events   : _ Double_bus.t = require_service world `Events   in
  let commands : _ Single_bus.t = require_service world `Commands in
  Single_bus.drain signals;
  Single_bus.drain commands;
  Double_bus.drain events
