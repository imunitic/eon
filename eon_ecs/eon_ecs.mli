module Entity_id : sig
  (** Unique, generational entity identifiers. *)
  include module type of Entity_id
end

module Component : sig
  (** Defines component metadata and typed storage. *)
  include module type of Component
end

module World : sig
  (** Central ECS world — manages entities, components, and resources. *)
  include module type of World
end

module Query : sig
  (** Iteration helpers for fetching component combinations. *)
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
  module type S = Bus.BUS
  (** Single-buffered bus implementation. *)
  module Single = Single_bus
  (** Double-buffered bus implementation. *)
  module Double = Double_bus
end

(** Single-buffered bus used for transient signals delivered within a frame. *)
module Signals = Single_bus
(** Double-buffered bus used for events delivered on the next frame. *)
module Events = Double_bus
(** Single-buffered bus used for same-frame command processing. *)
module Commands = Single_bus

module System : sig
  (** System definitions and helpers for attaching handlers to buses. *)
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

module Pipeline : sig
  (** Execution pipeline grouping systems into ordered phases. *)
  (** Signature exposed by pipelines. *)
  module type S = Pipeline.S
  (** Functor building custom pipeline implementations. *)
  module Make = Pipeline.Make
  (** Default pipeline for {!System.Default}. *)
  module Default : module type of Make (System.Default)
end

module Progress : sig
  (** Frame progression controllers (variable, fixed, hybrid). *)
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
  (** Control loop orchestrating collect → progress → drain → render. *)
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
  (** Renderer that performs no output. *)
  module Noop_renderer : RENDERER with type world = World.t and type result = unit
  (** Standard bus pack using the aliases exported above. *)
  module Default_buses : BUSES with type world = World.t
  (** Ready-to-use loop wired to defaults for the ECS core. *)
  module Default :
    module type of
      Make
        (Clock.Mtime)
        (Progress_adapter)
        (Noop_renderer)
        (Default_buses)
end
