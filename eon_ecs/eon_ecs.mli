(** {1 Eon.ECS — Entity Component System Core} *)

(** {2 Entities} *)

module Entity_id : sig
  (** Unique, generational entity identifiers. *)
  include module type of Entity_id
end

(** {2 Components} *)

module Component : sig
  (** Defines component metadata and typed storage. *)
  include module type of Component
end

(** {2 The World} *)

module World : sig
  (** Central ECS world — manages entities, components, and resources. *)
  include module type of World
end

module Entity_manager : sig
  include module type of Entity_manager
end

