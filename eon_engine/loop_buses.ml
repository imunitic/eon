module Signals  = Single_bus
module Events   = Double_bus
module Commands = Single_bus

type world = Eon_ecs.World.t

let require_service world name =
  match Eon_ecs.World.get_service world name with
  | Some service -> service
  | None ->
    failwith (Printf.sprintf "Loop_buses: missing service (hash:%d)"
                (Hashtbl.hash name land Stdlib.max_int))

let collect world =
  let signals  : _ Signals.t  = require_service world `Signals  in
  let events   : _ Events.t   = require_service world `Events   in
  let commands : _ Commands.t = require_service world `Commands in
  Signals.collect  signals;
  Events.collect   events;
  Commands.collect commands

let drain world =
  let signals  : _ Signals.t  = require_service world `Signals  in
  let events   : _ Events.t   = require_service world `Events   in
  let commands : _ Commands.t = require_service world `Commands in
  Signals.drain  signals;
  Commands.drain commands;
  Events.drain   events
