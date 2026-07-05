module Vec2 = struct
  type t = { x : float; y : float }

  let zero = { x = 0.0; y = 0.0 }
  let one  = { x = 1.0; y = 1.0 }

  let create x y = { x; y }

  let add   a b = { x = a.x +. b.x; y = a.y +. b.y }
  let sub   a b = { x = a.x -. b.x; y = a.y -. b.y }
  let mul   v s = { x = v.x *. s;   y = v.y *. s }
  let div   v s = { x = v.x /. s;   y = v.y /. s }
  let neg   v   = { x = -. v.x;     y = -. v.y }
  let mul_v a b = { x = a.x *. b.x; y = a.y *. b.y }

  let dot       a b = a.x *. b.x +. a.y *. b.y
  let length_sq v   = v.x *. v.x +. v.y *. v.y
  let length    v   = sqrt (length_sq v)

  let normalize v =
    let l = length v in
    if l = 0.0 then v else div v l

  let distance_sq a b = length_sq (sub b a)
  let distance    a b = sqrt (distance_sq a b)

  let perpendicular v = { x = -. v.y; y = v.x }

  let rotate v a =
    let cos_a = cos a and sin_a = sin a in
    { x = v.x *. cos_a -. v.y *. sin_a
    ; y = v.x *. sin_a +. v.y *. cos_a }

  let angle      v = atan2 v.y v.x
  let from_angle a = { x = cos a; y = sin a }

  let lerp a b t =
    { x = a.x +. (b.x -. a.x) *. t
    ; y = a.y +. (b.y -. a.y) *. t }

  let clamp v ~min:mn ~max:mx =
    { x = Float.max mn.x (Float.min mx.x v.x)
    ; y = Float.max mn.y (Float.min mx.y v.y) }

  let reflect v n =
    sub v (mul n (2.0 *. dot v n))

  let project v ~onto =
    mul onto (dot v onto /. length_sq onto)
end

module Vec2i = struct
  type t = { x : int; y : int }

  let zero = { x = 0; y = 0 }
  let one  = { x = 1; y = 1 }

  let create x y = { x; y }

  let add   a b = { x = a.x + b.x; y = a.y + b.y }
  let sub   a b = { x = a.x - b.x; y = a.y - b.y }
  let mul   v s = { x = v.x * s;   y = v.y * s }
  let neg   v   = { x = - v.x;     y = - v.y }
  let mul_v a b = { x = a.x * b.x; y = a.y * b.y }

  let to_vec2 v        = Vec2.create (float_of_int v.x) (float_of_int v.y)
  let of_vec2_floor v  = { x = int_of_float (floor v.Vec2.x); y = int_of_float (floor v.Vec2.y) }
  let of_vec2_round v  = { x = int_of_float (Float.round v.Vec2.x); y = int_of_float (Float.round v.Vec2.y) }
  let of_vec2_ceil  v  = { x = int_of_float (ceil v.Vec2.x); y = int_of_float (ceil v.Vec2.y) }
end

module Rect = struct
  type t = { x : float; y : float; w : float; h : float }

  let create x y w h = { x; y; w; h }

  let of_min_max (mn : Vec2.t) (mx : Vec2.t) =
    { x = mn.x; y = mn.y; w = mx.x -. mn.x; h = mx.y -. mn.y }

  let min r = Vec2.create r.x r.y
  let max r = Vec2.create (r.x +. r.w) (r.y +. r.h)
  let center r = Vec2.create (r.x +. r.w *. 0.5) (r.y +. r.h *. 0.5)

  let contains_point r (p : Vec2.t) =
    p.x >= r.x && p.x <= r.x +. r.w &&
    p.y >= r.y && p.y <= r.y +. r.h

  let intersects a b =
    not (a.x +. a.w < b.x || b.x +. b.w < a.x ||
         a.y +. a.h < b.y || b.y +. b.h < a.y)

  let intersection a b =
    let x0 = Float.max a.x b.x in
    let y0 = Float.max a.y b.y in
    let x1 = Float.min (a.x +. a.w) (b.x +. b.w) in
    let y1 = Float.min (a.y +. a.h) (b.y +. b.h) in
    if x1 > x0 && y1 > y0 then Some { x = x0; y = y0; w = x1 -. x0; h = y1 -. y0 }
    else None

  let translate r (v : Vec2.t) = { r with x = r.x +. v.x; y = r.y +. v.y }

  let expand r f = { x = r.x -. f; y = r.y -. f; w = r.w +. 2.0 *. f; h = r.h +. 2.0 *. f }

  let scale r f = { x = r.x *. f; y = r.y *. f; w = r.w *. f; h = r.h *. f }

  let merge a b =
    let x0 = Float.min a.x b.x in
    let y0 = Float.min a.y b.y in
    let x1 = Float.max (a.x +. a.w) (b.x +. b.w) in
    let y1 = Float.max (a.y +. a.h) (b.y +. b.h) in
    { x = x0; y = y0; w = x1 -. x0; h = y1 -. y0 }
end

module Circle = struct
  type t = { center : Vec2.t; radius : float }

  let create center radius = { center; radius }

  let contains_point c p =
    Vec2.distance_sq c.center p <= c.radius *. c.radius

  let intersects a b =
    let r = a.radius +. b.radius in
    Vec2.distance_sq a.center b.center <= r *. r

  let intersects_rect c r =
    let cx = Float.max r.Rect.x (Float.min c.center.Vec2.x (r.Rect.x +. r.Rect.w)) in
    let cy = Float.max r.Rect.y (Float.min c.center.Vec2.y (r.Rect.y +. r.Rect.h)) in
    let dx = c.center.Vec2.x -. cx in
    let dy = c.center.Vec2.y -. cy in
    dx *. dx +. dy *. dy <= c.radius *. c.radius
end

module Transform2D = struct
  type t = {
    position : Vec2.t;
    rotation : float;
    scale    : Vec2.t;
  }

  let identity = { position = Vec2.zero; rotation = 0.0; scale = Vec2.one }

  let create ~position ~rotation ~scale = { position; rotation; scale }

  let compose parent child = {
    position = Vec2.add parent.position (Vec2.rotate (Vec2.mul_v child.position parent.scale) parent.rotation);
    rotation = parent.rotation +. child.rotation;
    scale    = Vec2.mul_v parent.scale child.scale;
  }

  let apply_point t p =
    Vec2.add t.position (Vec2.rotate (Vec2.mul_v p t.scale) t.rotation)

  let inverse t =
    let inv_scale    = Vec2.create (1.0 /. t.scale.x) (1.0 /. t.scale.y) in
    let inv_rotation = -. t.rotation in
    { position = Vec2.mul_v (Vec2.rotate (Vec2.neg t.position) inv_rotation) inv_scale
    ; rotation = inv_rotation
    ; scale    = inv_scale
    }

  let position t = t.position
  let rotation t = t.rotation
  let scale    t = t.scale

  let lerp_angle a b t =
    let two_pi = 2.0 *. Float.pi in
    let diff   = mod_float (b -. a) two_pi in
    let diff   = if diff > Float.pi then diff -. two_pi
                 else if diff <= -. Float.pi then diff +. two_pi
                 else diff in
    a +. diff *. t

  let lerp a b t = {
    position = Vec2.lerp a.position b.position t;
    rotation = lerp_angle a.rotation b.rotation t;
    scale    = Vec2.lerp a.scale b.scale t;
  }
end
