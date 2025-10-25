module Signals = Single_bus
module Events = Double_bus
module Commands = Single_bus

type world = World.t

let hash_key key = Hashtbl.hash key land Stdlib.max_int

let require_service world name =
  match World.get_service world name with
  | Some service -> service
  | None ->
      let id = hash_key name in
      failwith (Printf.sprintf "Missing service (hash:%d)" id)

let collect world =
  let signals = require_service world `Signals in
  let events = require_service world `Events in
  let commands = require_service world `Commands in
  Signals.collect signals;
  Events.collect events;
  Commands.collect commands

let drain world =
  let signals = require_service world `Signals in
  let events = require_service world `Events in
  let commands = require_service world `Commands in
  Signals.drain signals;
  Commands.drain commands;
  Events.drain events
