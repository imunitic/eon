(** Engine-wide color type. All components are floats in [[0, 1]].

    Backends convert [Color.t] to their own internal representation at render
    time — e.g. Raylib's [Raylib.Color.create] takes ints in [[0, 255]]. *)

type t = { r : float; g : float; b : float; a : float }

val create : float -> float -> float -> float -> t
(** [create r g b a] — components in [[0, 1]]. *)

val white       : t
val black       : t
val transparent : t
(** Fully transparent black — useful as a tint or background default. *)
