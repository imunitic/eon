(** Component module signature for Eon Engine.

    This module defines the signature that all component modules must conform to.
    It represents the module-level interface, while Component_descriptor defines
    the descriptor-level operations.
*)

module type S = sig
  (** The type of the component's data structure. *)
  type t

  (** The component descriptor for registration with the world. *)
  val component : t Component_descriptor.t

  (** The name of the component as a string. *)
  val name : string
end
