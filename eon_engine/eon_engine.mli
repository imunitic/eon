(** Eon Engine public API. *)

module Query_backend = Query_backend

module Sparse_set_backend = Sparse_set_backend

module Query = Query

module View = View

module Components = Components

type entity_id = Eon_ecs.Entity_id.t

module World : sig
  module type S = World.S

  type t = World.t

  val create : unit -> t
  val create_entity : t -> entity_id
  val add_component : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val set_component : t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val get_component : t -> entity_id -> 'a Component_descriptor.t -> 'a option
  val remove_component : t -> entity_id -> 'a Component_descriptor.t -> unit
  val remove_all_components : t -> entity_id -> unit
  val destroy_entity : t -> entity_id -> unit
  val register : t -> 'a Component_descriptor.t -> Components.registration_result
  val is_registered : t -> 'a Component_descriptor.t -> bool
  val count_entities : t -> int
  val is_alive : t -> entity_id -> bool

  val add_data : t -> [> ] -> 'a -> unit
  val set_data : t -> [> ] -> 'a -> unit
  val get_data : t -> [> ] -> 'a option
  val count_data : t -> int
  val add_service : t -> [> ] -> 'a -> unit
  val get_service : t -> [> ] -> 'a option
  val list_services : t -> int list

  val iter_entities : t -> string list -> (entity_id -> unit) -> unit
  val has_component : t -> entity_id -> string -> bool
end

module Backend : sig
  module World : sig
    val to_raw : World.t -> Eon_ecs.World.t
  end
end

val component : string -> 'a Components.t

(** {2 Buses} *)

(** Engine bus signature — same as [Eon_ecs.Bus.S] but owned by the engine
    layer so it can evolve independently. *)
module Bus : sig
  module type S = Bus.S
end

(** Same-frame bus with mutex-protected [emit]. Satisfies [Bus.S]. *)
module Single_bus : module type of Single_bus

(** Next-frame bus with mutex-protected [emit]. Satisfies [Bus.S]. *)
module Double_bus : module type of Double_bus

(** Alias: same-frame signals bus. Same type as [Single_bus]. *)
module Signals  : module type of Single_bus

(** Alias: next-frame events bus. Same type as [Double_bus]. *)
module Events   : module type of Double_bus

(** Alias: same-frame commands bus. Same type as [Single_bus]. *)
module Commands : module type of Single_bus

(** {2 World capability} *)

(** Phantom capability wrapper around [World.t].
    Enforces read-only vs read-write access at compile time. *)
module World_cap : sig
  include module type of World_cap
end

(** {2 Executor} *)

(** Threading-substrate seam for the parallel pipeline. *)
module Executor : sig
  module type S = Executor.S
  module Sequential : Executor.S
end

(** {2 System} *)

(** Engine system — wraps any [Eon_ecs.System.S] with [World_cap] capabilities.

    Game code constructs systems via [System.Default.make]. Pass the result to
    [Pipeline.Default.add_system]. [System.Make] is for custom bus wiring. *)
module System : sig
  module type S        = System.S
  module type DISPATCH = System.DISPATCH

  (** Build an engine system module over a custom [Eon_ecs.System.S].
      Returns [DISPATCH] so it can be passed directly to [Pipeline.Make]. *)
  module Make (C : Eon_ecs.System.S) : System.DISPATCH
    with type kind = C.kind

  (** Default engine system wired with engine [Single_bus] / [Double_bus].
      Constrained to [S]; dispatch ops are pipeline-internal only. Use
      [System.Make(Eon_ecs.System.Make(Signals)(Events)(Commands))] explicitly
      when you need to pass the system module to [Pipeline.Make]. *)
  module Default : System.S with type kind = [ `Fixed | `Variable ]
end

(** {2 Pipeline} *)

(** Engine parallel pipeline — two-step dispatch per phase.

    Parallel systems run via [Executor.run_all] with read-only world access;
    exclusive systems run sequentially after, with read-write access. *)
module Pipeline : sig
  module type S = Pipeline.S

  (* Warning 67 suppressed permanently: Executor.S has no types, only
     run_all — OCaml's functor-usage check only tracks type references, so
     Executor is invisible to it regardless of implementation.
     Pass System.Make(Core) as the system argument; System.Default is
     constrained to S and cannot be passed here directly. *)
  [@@@warning "-67"]
  module Make
      (System   : System.DISPATCH)
      (Executor : Executor.S)
    : Pipeline.S
      with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
       and type kind = System.kind
  [@@@warning "+67"]

  (** Default pipeline: engine [System.Default] with [Executor.Sequential].
      [kind] is concrete so [run_by_filter ~filter:(fun k -> k = `Fixed)] works
      directly without reaching for [System.Make] / [Pipeline.Make]. *)
  module Default : Pipeline.S
    with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.Default.t
     and type kind = [ `Fixed | `Variable ]
end

(** {2 Progress} *)

(** Time-step progression manager for engine pipelines.
    Typed for [World.t]; mirrors [Eon_ecs.Progress]. *)
module Progress : sig
  include module type of Progress
end

(** {2 Loop} *)

(** Game loop builder for the engine layer.
    Delegates to [Eon_ecs.Loop.Make]; typed for [World.t] via [Progress] and
    [Loop_buses]. *)
module Loop : sig
  include module type of Loop
end

(** {2 Loop buses} *)

(** Engine bus orchestration for [Loop.Make].

    Satisfies [Loop.BUSES with type world = World.t]. Register
    [Single_bus] / [Double_bus] instances under [`` `Signals ``],
    [`` `Events ``], [`` `Commands ``] in the world before calling
    [Loop.run]. *)
module Loop_buses : sig
  include module type of Loop_buses
end
