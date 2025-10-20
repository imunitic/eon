module type BUS = sig
  (** Message bus abstraction with deterministic collect/drain semantics. *)

  (** Handle to a concrete bus instance carrying payloads of type ['msg]. *)
  type 'msg t

  (** Allocate a new empty bus. *)
  val create  : unit -> 'msg t

  (** Register a callback invoked when messages are drained. *)
  val on      : 'msg t -> ('msg -> unit) -> unit

  (** Enqueue a message for delivery. *)
  val emit    : 'msg t -> 'msg -> unit

  (** Prepare messages for the upcoming frame, respecting buffering policy. *)
  val collect : 'msg t -> unit

  (** Deliver and clear messages according to the bus semantics. *)
  val drain   : 'msg t -> unit
end
