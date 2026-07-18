(* Companion example for docs/eon_ecs chapter: Buses. *)

open Eon_ecs

(* Signals is a Single_bus: drain = collect, same-frame delivery.
   Whatever was emitted since the last drain fires on this drain. *)
let signals_same_frame () =
  let bus = Signals.create () in
  let fired = ref false in
  Signals.on bus (fun `Damage_taken -> fired := true);

  Signals.emit bus `Damage_taken;
  assert (not !fired);   (* not delivered yet — emit only enqueues *)
  Signals.drain bus;
  assert !fired           (* delivered: drain ran in the same "frame" as emit *)

(* Events is a Double_bus: emit writes to a "next" queue. drain delivers
   whatever is in "current", then swaps next -> current. An event
   emitted this frame is not visible until NEXT frame's drain. *)
let events_next_frame () =
  let bus = Events.create () in
  let fired = ref false in
  Events.on bus (fun `Level_up -> fired := true);

  Events.emit bus `Level_up;
  Events.drain bus;
  assert (not !fired);    (* frame N's drain: current was still empty *)

  Events.drain bus;
  assert !fired            (* frame N+1's drain: next -> current swap landed *)

(* Commands is also a Single_bus (same delivery timing as Signals) but
   is used by convention for "a system already knows the mutation to
   apply" rather than fan-out notifications. *)
let commands_mutate () =
  let bus = Commands.create () in
  let total = ref 0 in
  Commands.on bus (fun (`Add_gold n) -> total := !total + n);

  Commands.emit bus (`Add_gold 10);
  Commands.emit bus (`Add_gold 5);
  Commands.drain bus;
  assert (!total = 15)

(* Multiple subscribers on the same bus fire in registration order —
   the first subscriber registered runs first. *)
let subscriber_order () =
  let bus   = Signals.create () in
  let order = ref [] in
  Signals.on bus (fun `Ping -> order := !order @ [ 1 ]);   (* registered first *)
  Signals.on bus (fun `Ping -> order := !order @ [ 2 ]);   (* registered second *)
  Signals.emit bus `Ping;
  Signals.drain bus;
  assert (!order = [ 1; 2 ])   (* handler 1 (registered first) ran first *)

let () =
  signals_same_frame ();
  events_next_frame ();
  commands_mutate ();
  subscriber_order ()
