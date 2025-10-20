module Type_id : sig
  (** Type-safe identifiers assigned to services/resources. *)
  type t
end

(** Mutable store holding both services and arbitrary data. *)
type t

(** Existential wrapper pairing a service with a printer. *)
type packed = Pack : 'a * (unit -> string) -> packed

(** Create an empty resource store. *)
val create : unit -> t

(** Register a service under the given type identifier. *)
val add_service : t -> Type_id.t -> 'a -> unit

(** Retrieve a service by identifier. *)
val get_service : t -> Type_id.t -> 'a option

(** Remove a previously registered service. *)
val remove_service : t -> Type_id.t -> unit

(** List every service identifier currently stored. *)
val list_services : t -> Type_id.t list

(** Store arbitrary data under the provided integer key. *)
val add_data : t -> int -> 'a -> unit

(** Retrieve arbitrary data by key. *)
val get_data : t -> int -> 'a option

(** Remove data associated with the key. *)
val remove_data : t -> int -> unit

(** Iterate over every data entry. *)
val iter_data : (int -> 'a -> unit) -> t -> unit

(** Number of data entries stored. *)
val count_data : t -> int

(** Construct a {!Type_id.t} from a type name. *)
val of_typename : string -> Type_id.t
