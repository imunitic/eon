(** Concrete 2D math primitives. All types are exposed as records — use field
    access directly rather than accessor functions where possible.

    Five modules cover the full surface needed for 2D game math:
    - {!Vec2} — float 2D vector: position, velocity, direction, scale
    - {!Vec2i} — integer 2D vector: tile coordinates, grid positions
    - {!Rect} — axis-aligned bounding boxes
    - {!Circle} — circle for collision and spatial queries
    - {!Transform2D} — decomposed 2D transform for the hierarchy *)

module Vec2 : sig
  type t = { x : float; y : float }
  (** 2D float vector. Fields are public — read [v.x] and [v.y] directly. *)

  val zero : t
  (** [{x=0; y=0}] *)

  val one : t
  (** [{x=1; y=1}] *)

  val create : float -> float -> t

  (** {2 Arithmetic} *)

  val add   : t -> t -> t
  val sub   : t -> t -> t

  val mul : t -> float -> t
  (** Scalar multiply. *)

  val div : t -> float -> t
  (** Scalar divide. *)

  val neg : t -> t

  val mul_v : t -> t -> t
  (** Component-wise multiply — use for scale composition. *)

  (** {2 Geometric} *)

  val dot : t -> t -> float

  val length    : t -> float
  val length_sq : t -> float
  (** Squared length — avoids [sqrt]; prefer for comparisons and culling. *)

  val normalize : t -> t
  (** Returns a unit vector. Returns [v] unchanged if [v = zero]. *)

  val distance    : t -> t -> float
  val distance_sq : t -> t -> float
  (** Squared distance — avoids [sqrt]; prefer for comparisons. *)

  val clamp : t -> min:t -> max:t -> t
  (** Component-wise clamp. [clamp v ~min ~max] clamps each component of [v]
      independently between the corresponding components of [min] and [max]. *)

  val reflect : t -> t -> t
  (** [reflect v n] reflects [v] across the surface whose normal is [n].
      [n] must be a unit vector. Result: [v - 2*(v·n)*n]. *)

  val project : t -> onto:t -> t
  (** [project v ~onto] projects [v] onto [onto].
      [onto] does not need to be normalised.
      Passing [Vec2.zero] as [onto] produces [NaN] — the caller must ensure
      [onto] is non-zero. *)

  (** {2 Rotation} *)

  val perpendicular : t -> t
  (** [perpendicular v] returns [v] rotated 90° counter-clockwise: [{x = -v.y; y = v.x}].
      Useful for computing surface normals and steering forces. *)

  val rotate : t -> float -> t
  (** [rotate v angle] rotates [v] by [angle] radians counter-clockwise. *)

  val angle : t -> float
  (** Angle of the vector in radians, in the range [(-π, π\]]. Computed via [atan2]. *)

  val from_angle : float -> t
  (** Unit vector pointing in the direction of [angle] radians. *)

  (** {2 Interpolation} *)

  val lerp : t -> t -> float -> t
  (** [lerp a b t] — linear interpolation. [t=0] returns [a]; [t=1] returns [b]. *)
end

module Vec2i : sig
  type t = { x : int; y : int }
  (** 2D integer vector. Use for tile coordinates, grid positions, and any
      context where discrete coordinates are required (e.g. EDN-loaded level data). *)

  val zero : t
  val one  : t

  val create : int -> int -> t

  (** {2 Arithmetic} *)

  val add   : t -> t -> t
  val sub   : t -> t -> t

  val mul : t -> int -> t
  (** Scalar multiply. *)

  val neg : t -> t

  val mul_v : t -> t -> t
  (** Component-wise multiply. *)

  (** {2 Conversion} *)

  val to_vec2 : t -> Vec2.t
  (** Exact conversion — no precision loss. *)

  val of_vec2_floor : Vec2.t -> t
  (** Convert float vector to tile coordinates by flooring each component.
      Use when mapping a world position to the tile it occupies. *)

  val of_vec2_round : Vec2.t -> t
  (** Convert float vector to integer by rounding each component. *)

  val of_vec2_ceil : Vec2.t -> t
  (** Convert float vector to integer by ceiling each component. *)
end

module Rect : sig
  type t = { x : float; y : float; w : float; h : float }
  (** Axis-aligned bounding box with origin at the top-left corner. *)

  val create : float -> float -> float -> float -> t
  (** [create x y w h] *)

  val of_min_max : Vec2.t -> Vec2.t -> t
  (** Construct from min (top-left) and max (bottom-right) corners. *)

  (** {2 Accessors} *)

  val min : t -> Vec2.t
  (** Top-left corner — same as [{x; y}]. *)

  val max : t -> Vec2.t
  (** Bottom-right corner — same as [{x+w; y+h}]. *)

  val center : t -> Vec2.t

  (** {2 Queries} *)

  val contains_point : t -> Vec2.t -> bool
  val intersects     : t -> t -> bool

  val intersection : t -> t -> t option
  (** [Some r] where [r] is the overlapping area, or [None] if disjoint. *)

  (** {2 Transform} *)

  val translate : t -> Vec2.t -> t

  val expand : t -> float -> t
  (** [expand r f] pads all four sides by [f] — negative [f] shrinks. *)

  val scale : t -> float -> t
  (** [scale r f] scales position and dimensions by [f] around the origin.
      Use for camera zoom and UI scaling. *)

  val merge : t -> t -> t
  (** Smallest rect containing both inputs. Use for bounding-box accumulation. *)
end

module Circle : sig
  type t = { center : Vec2.t; radius : float }
  (** Circle shape for collision detection and spatial queries. *)

  val create : Vec2.t -> float -> t
  (** [create center radius]. Radius is squared internally for intersection
      tests — a negative radius is treated as its absolute value. *)

  val contains_point : t -> Vec2.t -> bool

  val intersects : t -> t -> bool
  (** Circle-circle intersection test. *)

  val intersects_rect : t -> Rect.t -> bool
  (** Circle-AABB intersection test. True if the circle and rect overlap. *)
end

module Transform2D : sig
  type t = {
    position : Vec2.t;
    rotation : float;   (** Radians. *)
    scale    : Vec2.t;
  }
  (** Decomposed 2D transform. Preferred over a 2×3 matrix for game-layer
      code — readable, sufficient for all 2D use cases, no matrix decomposition
      needed. Shear is not supported. *)

  val identity : t
  (** Zero translation, zero rotation, unit scale. *)

  val create : position:Vec2.t -> rotation:float -> scale:Vec2.t -> t

  (** {2 Hierarchy operations} *)

  val compose : t -> t -> t
  (** [compose parent child] produces the world-space transform of [child]
      given its [parent]'s world transform (full TRS):
      {[
        position = parent.position + rotate(child.position * parent.scale, parent.rotation)
        rotation = parent.rotation + child.rotation
        scale    = Vec2.mul_v parent.scale child.scale
      ]}
      The parent defines a complete coordinate space: scaling the parent
      stretches both the child's visual size and its offset distance, matching
      the behaviour of Unity, Godot, and Bevy. This is the hot-path operation
      called by [Transform_system] on every entity in the hierarchy every frame. *)

  val apply_point : t -> Vec2.t -> Vec2.t
  (** Transform a point from local space to world space (full TRS: scale, rotate, translate).
      [apply_point (compose parent child) p = apply_point parent (apply_point child p)]
      holds only for uniform scale — non-uniform scale breaks the composition law,
      a known limitation shared by Unity, Godot, and Bevy. *)

  val inverse : t -> t
  (** Inverse transform — converts world space back to local space.
      [compose t (inverse t)] is approximately [identity] within float
      tolerance. Use for world→local coordinate conversion (picking, physics).
      Precondition: both components of [t.scale] must be non-zero.
      A zero scale collapses space and has no inverse — the result is undefined
      ([infinity] or [NaN]). *)

  (** {2 Field accessors} *)

  val position : t -> Vec2.t
  val rotation : t -> float
  val scale    : t -> Vec2.t

  (** {2 Interpolation} *)

  val lerp_angle : float -> float -> float -> float
  (** [lerp_angle a b t] — shortest-path interpolation between two angles in
      radians. Always rotates via the shorter arc, correctly handling the
      [±π] boundary. Use this when interpolating a rotation angle directly
      without a full transform. *)

  val lerp : t -> t -> float -> t
  (** [lerp a b t] — linear interpolation across all fields using shortest-path
      rotation via {!lerp_angle}. Safe across the [±π] boundary. [t=0] returns
      [a]; [t=1] returns angle-equivalent to [b]. *)
end
