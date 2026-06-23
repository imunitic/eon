(** Eon ECS public API.

    This module is the canonical entry-point for users of the [eon-ecs] package.
    It re-exports core modules and provides a default stack for systems, pipelines,
    progress controllers, and loop orchestration.

    Typical default-stack setup:
    {[
      module World    = Eon_ecs.World
      module System   = Eon_ecs.System.Default
      module Pipeline = Eon_ecs.Pipeline.Default
      module Progress = Eon_ecs.Progress.Default
      module Loop     = Eon_ecs.Loop.Default
      module Signals  = Eon_ecs.Signals
      module Events   = Eon_ecs.Events
      module Commands = Eon_ecs.Commands

      let world = World.create ()
    ]}
*)

module Entity_id : sig
  (** Unique, generational entity identifiers.

      Entity identifiers are opaque values containing:
      - an entity slot index
      - a generation counter used to prevent stale-handle reuse

      Example:
      {[
        let e = Eon_ecs.Entity_id.make 4 2 in
        assert (Eon_ecs.Entity_id.index e = 4);
        assert (Eon_ecs.Entity_id.generation e = 2)
      ]}
  *)
  include module type of Entity_id
end

module Component : sig
  (** Typed component metadata and storage wrappers.

      Components are registered in the world by [name] and [id], then mapped to
      sparse-set storage internally.

      Example:
      {[
        let world = Eon_ecs.World.create () in
        ignore (Eon_ecs.World.register_component world ~name:"Position" ~id:0)
      ]}
  *)
  include module type of Component
end

module World : sig
  (** Central ECS state container.

      [World] owns:
      - entities and their lifecycle
      - component registration and per-entity attachments
      - resource stores for data and long-lived services

      Example:
      {[
        let world = Eon_ecs.World.create () in
        ignore (Eon_ecs.World.register_component world ~name:"Health" ~id:0);
        let e = Eon_ecs.World.create_entity world in
        Eon_ecs.World.add_component world e ~name:"Health" 100
      ]}
  *)
  include module type of World
end

module Query : sig
  (** Iteration and counting helpers over component intersections.

      Example:
      {[
        Eon_ecs.Query.iter1 world "Position"
          (fun entity (x, y) ->
             ignore entity;
             ignore (x, y))
      ]}
  *)
  include module type of Query
end

module Clock : sig
  (** Time sources used by the ECS loop. *)
  (** Abstract clock returning seconds. *)
  module type S = Clock.S
  (** Clock backed by [Mtime_clock]. *)
  module Mtime : S
end

module Bus : sig
  (** Message bus abstractions with collect/drain semantics. *)
  (** Common bus signature exposed from the core. *)
  module type S = Bus.S
  (** Single-buffered bus implementation. *)
  module Single = Single_bus
  (** Double-buffered bus implementation. *)
  module Double = Double_bus
end

(** Single-buffered bus used for transient same-frame notifications.

    [Signals.emit] can be consumed by [Signals.collect] or [Signals.drain] in the
    same frame, depending on loop orchestration.

    Use signals for transient notifications or fan-out where one or more systems
    may react, rather than for directly describing a required mutation.
*)
module Signals = Single_bus
(** Double-buffered bus for next-frame reactions.

    Emissions are staged and become visible after the next [collect]/[drain] cycle.

    Use events when reactions should follow the double-buffer next-frame delivery
    semantics.
*)
module Events = Double_bus
(** Single-buffered bus for same-frame command handling.

    Commands are the preferred bus for describing intended effects when a system
    already knows the mutation to apply. Keep world mutation in command handlers.
 *)
module Commands = Single_bus

module Dependency_graph : sig
  (** Generic directed acyclic graph with topological sort.

      Used internally by {!Pipeline.Make} for phase ordering and exposed as a
      public primitive so higher-level layers ({e e.g.} [eon_engine]) can reuse
      the same topo-sort logic without duplicating it.

      Example:
      {[
        open Eon_ecs.Dependency_graph

        let g =
          create ()
          |> add_node `A
          |> add_node `B
          |> add_node `C
          |> before ~earlier:`A ~later:`B
          |> before ~earlier:`B ~later:`C

        let order = topo_sort g  (* [`A; `B; `C] *)
      ]}
  *)
  include module type of Dependency_graph
end

module System : sig
  (** System definitions and reactive bus handlers.

      [System.Default] is the most common choice and is wired to
      {!Signals}, {!Events}, and {!Commands}.

      Example:
      {[
        module System = Eon_ecs.System.Default

        let s =
          System.make
            ~update:(fun _world _dt -> ())
            ~kind:`Variable
            ()
      ]}
  *)
  (** Signature implemented by concrete systems. *)
  module type S = System.S
  (** Enumeration of system kinds used for scheduling. *)
  module type KIND = System.KIND

  (** Built-in kind mapping for fixed/variable systems. *)
  module Base_kind : module type of System.Base_kind
  (** Functor for constructing systems with custom kind tags. *)
  module Make_with_kinds : module type of System.Make_with_kinds
  (** Functor for building systems over the provided bus implementations. *)
  module Make = System.Make
  (** Default system stack wired to {!Signals}, {!Events}, and {!Commands}. *)
  module Default : module type of Make (Signals) (Events) (Commands)
end

module Buses : sig
  (** Polymorphic singleton bus instances for signals, events, and commands.

      [Default] provides the standard local bus family. Apply [Make] with
      remote transport modules for the multiplayer use case. *)
  module Make = Buses.Make
  module Default : module type of Buses.Default
end

module Pipeline : sig
  (** Ordered execution graph for systems.

      Pipelines define:
      - phases
      - phase dependencies
      - systems assigned to phases

      Example:
      {[
        module Pipeline = Eon_ecs.Pipeline.Default

        let pipeline =
          Pipeline.create ()
          |> Pipeline.add_phase `Input
          |> Pipeline.add_phase `Gameplay
          |> Pipeline.before ~earlier:`Input ~later:`Gameplay
      ]}
  *)
  (** Signature exposed by pipelines. *)
  module type S = Pipeline.S
  (** Functor building custom pipeline implementations. *)
  module Make = Pipeline.Make
  (** Default pipeline for {!System.Default} wired to {!Buses.Default}. *)
  module Default : module type of Make (System.Default) (Buses.Default)
end

module Progress : sig
  (** Time progression controllers over pipelines.

      Modes:
      - [Variable]: run variable systems once per frame
      - [Fixed step]: run fixed systems at deterministic step size
      - [Hybrid step]: run fixed systems at [step], then variable once/frame

      Example:
      {[
        module Progress = Eon_ecs.Progress.Default
        let progress = Progress.create ~mode:(Progress.Hybrid 0.016) pipeline
      ]}
  *)
  (** Signature implemented by time modes. *)
  module type S = Progress.TIME_MODE
  (** Functor producing progress controllers for custom kind sets. *)
  module Make_with_kind : module type of Progress.Make_with_kind
  (** Functor binding progress controllers to the default kind set. *)
  module Make = Progress.Make
  (** Default progress controller over {!Pipeline.Default}. *)
  module Default : module type of Make (Pipeline.Default)
end

module Loop : sig
  (** Control loop orchestration.

      Frame order in default wiring:
      1. collect Signals -> Events -> Commands
      2. tick Progress
      3. drain Signals -> Commands -> Events
      4. render

      Example:
      {[
        module Loop = Eon_ecs.Loop.Default

        let final_world =
          Loop.run
            ~progress
            ~world
            ~should_continue:(fun _world () -> false)
            ()
      ]}
  *)
  (** Clock signature required by loop implementations. *)
  module type CLOCK = Loop.CLOCK
  (** Renderer signature consumed by loop implementations. *)
  module type RENDERER = Loop.RENDERER
  (** Bus orchestration signature consumed by loop implementations. *)
  module type BUSES = Loop.BUSES
  (** Functor producing a loop from its clock, progress, renderer, and buses. *)
  module Make = Loop.Make
  module Progress_adapter : sig
    (** Reuse default progress controller internals for the loop functor. *)
    (** Type alias for the underlying progress controller. *)
    type 'phase t = 'phase Progress.Default.t
    (** World type expected by the adapter. *)
    type world = World.t
    (** Delegate to {!Progress.Default.tick}. *)
    val tick : 'phase t -> world:world -> dt:float -> world
  end
  (** Default bus collect/drain ordering (Signals -> Events -> Commands collect;
      Signals -> Commands -> Events drain). *)
  module Default_buses : BUSES
  (** Renderer that performs no output. *)
  module Noop_renderer : RENDERER with type world = World.t and type result = unit
  (** Ready-to-use loop wired to defaults for the ECS core. *)
  module Default :
    module type of
      Make
        (Clock.Mtime)
        (Progress_adapter)
        (Noop_renderer)
        (Default_buses)
end
