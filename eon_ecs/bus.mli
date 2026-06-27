module type S = sig
  (** Message bus abstraction with deterministic collect/drain semantics.

      Bus implementations differ in when emitted messages become visible:
      - single-buffered: same frame
      - double-buffered: next frame
  *)

  (** Handle to a concrete bus instance carrying payloads of type ['msg]. *)
  type 'msg t

  (** Allocate a new empty bus. *)
  val create  : unit -> 'msg t

  (** Register a callback invoked on message delivery.

      Subscribers are called in reverse registration order
      (most recently registered first). *)
  val on      : 'msg t -> ('msg -> unit) -> unit

  (** Remove all registered subscribers.

      After [clear], no callbacks fire on the next [drain] or [collect] until
      [on] is called again. Use this before re-registering systems (e.g. on
      scene transitions) via {!Pipeline.S.reset}. *)
  val clear   : 'msg t -> unit

  (** Enqueue a message for delivery. *)
  val emit    : 'msg t -> 'msg -> unit

  (** Collect messages according to the buffering policy. *)
  val collect : 'msg t -> unit

  (** Deliver and clear messages according to the bus semantics.

      Example:
      {[
        let bus = Commands.create () in
        Commands.on bus (fun cmd -> ignore cmd);
        Commands.emit bus `Tick;
        Commands.drain bus
      ]}
  *)
  val drain   : 'msg t -> unit
end
