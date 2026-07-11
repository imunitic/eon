(** Eon Engine public API. *)

(** {2 Math} *)

(** Concrete 2D math primitives: [Vec2], [Rect], and [Transform2D].
    No signatures or functors — these are value types embedded in components. *)
module Math : module type of Math

module Query_backend = Query_backend

module Sparse_set_backend = Sparse_set_backend

module Query = Query

module View = View

module Components = Components

type entity_id = Eon_ecs.Entity_id.t

module World : sig
  module type S = World.S

  type ro = World.ro
  type rw = World.rw
  type 'perm t = 'perm World.t

  val create   : unit -> rw t
  val readonly : rw t -> ro t

  (** {2 Read operations — accept any capability} *)

  val get_component        : 'perm t -> entity_id -> 'a Component_descriptor.t -> 'a option
  val is_alive             : 'perm t -> entity_id -> bool
  val is_registered        : 'perm t -> 'a Component_descriptor.t -> bool
  val count_entities       : 'perm t -> int

  val get_data      : 'perm t -> [> ] -> 'a option
  val count_data    : 'perm t -> int
  val get_service   : 'perm t -> [> ] -> 'a option
  val list_services : 'perm t -> int list

  val iter_entities : 'perm t -> string list -> (entity_id -> unit) -> unit
  val has_component : 'perm t -> entity_id -> string -> bool

  (** {2 Write operations — require [rw] capability} *)

  val create_entity        : rw t -> entity_id
  val destroy_entity       : rw t -> entity_id -> unit
  val add_component        : rw t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val set_component        : rw t -> entity_id -> 'a Component_descriptor.t -> 'a -> unit
  val remove_component     : rw t -> entity_id -> 'a Component_descriptor.t -> unit
  val remove_all_components: rw t -> entity_id -> unit
  val register             : rw t -> 'a Component_descriptor.t -> Components.registration_result

  val add_data    : rw t -> [> ] -> 'a -> unit
  val set_data    : rw t -> [> ] -> 'a -> unit
  val add_service : rw t -> [> ] -> 'a -> unit
end

val component : string -> 'a Components.t

(** {2 Resource and Service} *)

(** Typed, phantom-constrained resource accessors for world-scoped per-frame data. *)
module Resource : module type of Resource

(** Typed, phantom-constrained service accessors for long-lived singletons. *)
module Service : module type of Service

(** Flat world directory for cross-world access.

    Composes with [Resource.fetch] / [Service.fetch]:
    {[
      Resource.fetch (Namespace.named "global" ns) (module Raw_input_frame)
    ]} *)
module Namespace : module type of Namespace

(** Conventional name for the global world in a [Namespace.t].
    A string constant only — the engine creates no pre-made global world. *)
val default_global_ns : string

(** {2 Buses} *)

(** Engine bus signature — same as [Eon_ecs.Bus.S] but owned by the engine
    layer so it can evolve independently. *)
module Bus : sig
  module type S = Bus.S
end

(** Engine bus family — mutex-wrapped singleton instances. *)
module Buses : sig
  module Make = Buses.Make
  module Default : module type of Buses.Default
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

(** {2 Executor} *)

(** Threading-substrate seam for the parallel pipeline. *)
module Executor : sig
  module type S = Executor.S
  module Sequential : Executor.S
  module Domain_pool : sig
    val recommended_size : unit -> int
    [@@@warning "-67"]
    module Make (Config : sig val size : int end) : Executor.S
    [@@@warning "+67"]
  end
end

(** {2 System} *)

(** Engine system — wraps any [Eon_ecs.System.S] with [World] capability types.

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

  (** Module signature for parallel system definition files.

      [update] receives [World.ro World.t]; the pipeline dispatches it
      concurrently with other parallel systems in the phase.
      {[
        (* systems/query_system.ml *)
        type signal  = unit
        type event   = unit
        type command = [ `Move of entity_id * float * float ]

        let on_signal  _ _ = ()
        let on_event   _ _ = ()
        let on_command world = function `Move (e, dx, dy) -> ...

        let update (world : World.ro World.t) dt =
          Query.from world |> Query.iter (fun view -> ...)
      ]} *)
  module type Parallel_def = System.Parallel_def

  (** Module signature for exclusive system definition files.

      [update] receives [World.rw World.t]; runs sequentially after all
      parallel systems in the same phase have completed.
      {[
        (* systems/spawn_system.ml *)
        let update (world : World.rw World.t) dt =
          ignore (World.create_entity world)
      ]} *)
  module type Exclusive_def = System.Exclusive_def

  (** Build parallel/exclusive [make] functions for a custom [DISPATCH] implementation. *)
  module Make_factory (Sys : DISPATCH) : sig
    val make_parallel :
      (module Parallel_def
         with type signal  = 's
          and type event   = 'e
          and type command = 'c) ->
      ('s, 'e, 'c) Sys.t

    val make_exclusive :
      (module Exclusive_def
         with type signal  = 's
          and type event   = 'e
          and type command = 'c) ->
      ('s, 'e, 'c) Sys.t
  end

  (** Assemble a parallel system module into a [Default.t].
      {[
        |> Pipeline.Default.add_system `Gameplay (System.make_parallel (module Movement_system))
      ]} *)
  val make_parallel :
    (module Parallel_def
       with type signal  = 's
        and type event   = 'e
        and type command = 'c) ->
    ('s, 'e, 'c) Default.t

  (** Assemble an exclusive system module into a [Default.t].
      {[
        |> Pipeline.Default.add_system `Gameplay (System.make_exclusive (module Spawn_system))
      ]} *)
  val make_exclusive :
    (module Exclusive_def
       with type signal  = 's
        and type event   = 'e
        and type command = 'c) ->
    ('s, 'e, 'c) Default.t
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
      (Buses : sig
        val signals         : unit -> 'a System.Signal_bus.t
        val events          : unit -> 'a System.Event_bus.t
        val commands        : unit -> 'a System.Command_bus.t
        val unsubscribe_all : unit -> unit
      end)
    : Pipeline.S
      with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.t
       and type kind = System.kind
       and type world = World.rw World.t
  [@@@warning "+67"]

  (** Default pipeline: engine [System.Default] with [Executor.Sequential].
      [kind] is concrete so [run_by_filter ~filter:(fun k -> k = `Fixed)] works
      directly without reaching for [System.Make] / [Pipeline.Make]. *)
  module Default : Pipeline.S
    with type ('s, 'e, 'c) system_t = ('s, 'e, 'c) System.Default.t
     and type kind = [ `Fixed | `Variable ]
     and type world = World.rw World.t
end

(** {2 Time} *)

(** Frame-level time resource — [delta], [elapsed], [frame].

    [Progress.Make_with_time] seeds the resource automatically on the first tick.
    Fetch in systems via [Time.fetch world]. *)
module Time : module type of Time

(** {2 Progress} *)

(** Time-step progression manager for engine pipelines.
    Typed for [World.rw World.t]; mirrors [Eon_ecs.Progress].

    Use [Default] for no Time resource. Use [Default_with_time] for automatic
    [Time] writes before each tick — seeds the resource on the first tick,
    no manual pre-initialisation needed.

    [Make] / [Make_with_time] are available for custom pipeline wiring. *)
module Progress : sig
  include module type of Progress
  module Default           : module type of Eon_ecs.Progress.Make(Pipeline.Default)
  module Default_with_time : module type of Eon_ecs.Progress.Make(Pipeline.Default)
end

(** {2 Assets} *)

(** Asset lookup — maps logical string ids to absolute file paths.
    Passed to backends at [init] time for pre-loading. *)
module Asset_lookup : module type of Asset_lookup

(** {2 Audio} *)

(** Audio command vocabulary — [Play_sound], [Stop_sound], [Play_music], etc. *)
module Audio_command : module type of Audio_command

(** Per-frame audio command accumulator; stored in the world data plane. *)
module Audio_command_buffer : module type of Audio_command_buffer

(** Audio backend seam with [Null] implementation. *)
module Audio_backend : module type of Audio_backend

(** {2 Input} *)

(** Engine-defined keyboard keys — backend-agnostic. *)
module Key : module type of Key

(** Engine-defined mouse buttons — backend-agnostic. *)
module Mouse_button : module type of Mouse_button

(** Engine-defined gamepad buttons — backend-agnostic. *)
module Gamepad_button : module type of Gamepad_button

(** Immutable raw input snapshot written into the world once per frame. *)
module Raw_input_frame : module type of Raw_input_frame

(** Input backend seam with [Null] and [Scripted] implementations. *)
module Input_backend : module type of Input_backend

(** {2 Rendering} *)

(** Floating-point RGBA color. Components are in [[0, 1]]. *)
module Color : module type of Color

(** Backend-agnostic 2D render command set.
    Backends extend via polymorphic variant inclusion. *)
module Render_commands : module type of Render_commands

(** Ordered render command buffer — world-space and screen-space lists.
    Also owns [fetch], [fetch_opt], and [store] for world resource access. *)
module Render_stream : module type of Render_stream

(** Non-fatal errors from a render call. *)
module Rendering_result : module type of Rendering_result

(** Rendering backend seam with [Null] implementation. *)
module Rendering_backend : module type of Rendering_backend

(** Phase-ordered collector runner for [Render_stream]. *)
module Render_stream_collector : module type of Render_stream_collector

(** ECS system that populates and stores a [Render_stream] each frame.
    [Make(B)] produces a system typed for [B.command]. *)
module Render_system : module type of Render_system

(** {2 Transform & Lifecycle} *)

(** Payload types and helpers for transform hierarchy commands and setup. *)
module Transform_hierarchy : sig
  type reparent = {
    entity     : entity_id;
    new_parent : entity_id option;
    (** [None] detaches the entity, making it a root. *)
  }

  val despawn_recursive :
    'perm World.t ->
    entity_id ->
    emit:([ `Destroy_entity of entity_id ] -> unit) ->
    unit
  (** [despawn_recursive world entity ~emit] emits [`Destroy_entity] for every
      node in the subtree rooted at [entity], deepest nodes first.

      Call from a system [update]. [emit] is typically
      [Single_bus.emit (Buses.Default.commands ())]. Safe from a Parallel
      system: reads only, no [rw] required. *)

  val attach :
    World.rw World.t ->
    parent:entity_id ->
    child:entity_id ->
    unit
  (** [attach world ~parent ~child] synchronously sets [Parent] on [child] and
      adds [child] to [parent]'s [Children] list.

      For world setup before the simulation loop. Use [`Reparent] commands
      during simulation. *)
end

(** ECS system that maintains the transform hierarchy (DFS world-transform propagation).

    Register this system BEFORE [Lifecycle_system]: [Single_bus] dispatches in
    pipeline registration order (FIFO), so this system's handler fires first —
    detaching children before [Lifecycle_system] removes the entity.
    Use [Make] for a custom [DISPATCH]. *)
module Transform_system : sig
  module Make (Sys : System.DISPATCH) : sig
    val make : unit -> (unit, unit, [> `Reparent of Transform_hierarchy.reparent | `Destroy_entity of entity_id ]) Sys.t
  end

  module Default : sig
    val make : unit -> (unit, unit, [> `Reparent of Transform_hierarchy.reparent | `Destroy_entity of entity_id ]) System.Default.t
  end
end

(** ECS system that processes [`Destroy_entity] commands.

    Guards with [World.is_alive] — duplicate destroy commands for the same entity
    are safe. Register AFTER [Transform_system]: [Single_bus] dispatches in
    pipeline registration order (FIFO), so [Transform_system]'s handler fires
    first — detaching children before this system removes the entity.
    Use [Make] for a custom [DISPATCH]. *)
module Lifecycle_system : sig
  module Make (Sys : System.DISPATCH) : sig
    val make :
      ?on_command:(World.rw World.t -> ([> `Destroy_entity of entity_id ] as 'c) -> unit) ->
      unit ->
      (unit, unit, 'c) Sys.t
  end

  module Default : sig
    val make :
      ?on_command:(World.rw World.t -> ([> `Destroy_entity of entity_id ] as 'c) -> unit) ->
      unit ->
      (unit, unit, 'c) System.Default.t
  end
end

(** {2 Prefab} *)

(** Generic prefab loading: [Prefab.Make(Source)(Document_shape)] gives
    [load]/[register_component], with [raw_data] an associated type — not
    tied to EDN or any specific format. Build your own instantiation
    against this for a non-EDN prefab format. See
    [docs/design/prefab_system_design.md]. *)
module Prefab : module type of Prefab

(** The pre-built EDN instantiation of [Prefab.Make] — [eon_engine]'s
    "out of the box" prefab loading path, for the common case. Most
    consumers only need this one. [Prefab_edn.Make(Root)], not a single
    fixed module, since a game needs to point it at its own prefabs
    directory. Its [Source]/[Document_shape] implementations
    ([Edn_source]/[Edn_document]) are internal — not part of the public
    API, since nothing needs to reuse them independently of [Prefab_edn]
    today. *)
module Prefab_edn : module type of Prefab_edn

(** Opt-in default deserializers for the engine's prefab-authorable
    components ([Velocity], [Local_transform], [Collider], [Sprite],
    [Animation], [Camera], [Tag]) — not auto-registered, call
    [register_all] explicitly if you want them. *)
module Prefab_edn_defaults : module type of Prefab_edn_defaults

(** {2 Platform} *)

(** Platform seam — bundles input, audio, and rendering backends for [Loop.Make]. *)
module Platform : module type of Platform

(** {2 Loop} *)

(** Game loop builder for the engine layer. Collects input, ticks the
    pipeline, drains buses, and calls the renderer each frame. *)
module Loop : sig
  include module type of Loop
end

(** {2 Loop buses} *)

(** Engine bus orchestration for [Loop.Make].

    Satisfies [Loop.BUSES]. Bus instances are closed over from [Buses.Default]
    at module init time — no world argument required. *)
module Loop_buses : sig
  include module type of Loop_buses
end

