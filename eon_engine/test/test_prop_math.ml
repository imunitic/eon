open Eon_engine.Math

let eps = 1e-6

let float_eq a b = Float.abs (a -. b) < eps

let vec2_eq (a : Vec2.t) (b : Vec2.t) = float_eq a.x b.x && float_eq a.y b.y

let transform_eq (a : Transform2D.t) (b : Transform2D.t) =
  vec2_eq a.position b.position &&
  float_eq a.rotation b.rotation &&
  vec2_eq a.scale b.scale

let gen_float = QCheck.Gen.(float_range (-100.0) 100.0)

let gen_nonzero_float =
  QCheck.Gen.(map (fun f -> if Float.abs f < 0.01 then 1.0 else f) gen_float)

let gen_vec2 =
  QCheck.Gen.(map2 Vec2.create gen_float gen_float)

let gen_transform =
  QCheck.Gen.(map3
    (fun pos rot sx ->
      Transform2D.create
        ~position:pos
        ~rotation:rot
        ~scale:(Vec2.create sx (sx +. 0.5)))
    gen_vec2
    gen_float
    gen_nonzero_float)

let arb_vec2      = QCheck.make gen_vec2
let arb_float     = QCheck.make gen_float
let arb_transform = QCheck.make gen_transform

(* ------------------------------------------------------------------ *)
(* Vec2 properties                                                      *)
(* ------------------------------------------------------------------ *)

let prop_vec2_add_commutative =
  QCheck.Test.make ~name:"Vec2 add commutative" ~count:1_000
    (QCheck.pair arb_vec2 arb_vec2)
    (fun (a, b) -> vec2_eq (Vec2.add a b) (Vec2.add b a))

let prop_vec2_add_associative =
  QCheck.Test.make ~name:"Vec2 add associative" ~count:1_000
    (QCheck.triple arb_vec2 arb_vec2 arb_vec2)
    (fun (a, b, c) ->
       vec2_eq (Vec2.add (Vec2.add a b) c) (Vec2.add a (Vec2.add b c)))

let prop_vec2_mul_div_roundtrip =
  QCheck.Test.make ~name:"Vec2 mul/div round-trip" ~count:1_000
    (QCheck.pair arb_vec2 (QCheck.make gen_nonzero_float))
    (fun (v, s) -> vec2_eq (Vec2.div (Vec2.mul v s) s) v)

let prop_vec2_length_sq_eq_length_squared =
  QCheck.Test.make ~name:"Vec2 length_sq = length^2" ~count:1_000
    arb_vec2
    (fun v -> float_eq (Vec2.length_sq v) (Vec2.length v *. Vec2.length v))

let prop_vec2_normalize_unit_length =
  QCheck.Test.make ~name:"Vec2 normalize produces unit length" ~count:1_000
    (QCheck.make gen_nonzero_float |> QCheck.map (fun s -> Vec2.create s (s +. 1.0)))
    (fun v -> float_eq (Vec2.length (Vec2.normalize v)) 1.0)

let prop_vec2_from_angle_angle_roundtrip =
  QCheck.Test.make ~name:"Vec2 from_angle/angle round-trip" ~count:1_000
    (QCheck.make QCheck.Gen.(float_range (-.Float.pi) Float.pi))
    (fun a -> float_eq (Vec2.angle (Vec2.from_angle a)) a)

let prop_vec2_lerp_at_zero =
  QCheck.Test.make ~name:"Vec2 lerp t=0 returns a" ~count:1_000
    (QCheck.pair arb_vec2 arb_vec2)
    (fun (a, b) -> vec2_eq (Vec2.lerp a b 0.0) a)

let prop_vec2_lerp_at_one =
  QCheck.Test.make ~name:"Vec2 lerp t=1 returns b" ~count:1_000
    (QCheck.pair arb_vec2 arb_vec2)
    (fun (a, b) -> vec2_eq (Vec2.lerp a b 1.0) b)

(* ------------------------------------------------------------------ *)
(* Vec2 new function properties                                         *)
(* ------------------------------------------------------------------ *)

let prop_vec2_perpendicular_double =
  QCheck.Test.make ~name:"Vec2 perpendicular twice = negation" ~count:1_000
    arb_vec2
    (fun v -> vec2_eq (Vec2.perpendicular (Vec2.perpendicular v)) (Vec2.neg v))

let prop_vec2_perpendicular_length =
  QCheck.Test.make ~name:"Vec2 perpendicular preserves length" ~count:1_000
    arb_vec2
    (fun v -> float_eq (Vec2.length (Vec2.perpendicular v)) (Vec2.length v))

let prop_vec2_clamp_idempotent =
  QCheck.Test.make ~name:"Vec2 clamp is idempotent" ~count:1_000
    arb_vec2
    (fun v ->
       let mn = Vec2.create (-10.0) (-10.0) and mx = Vec2.create 10.0 10.0 in
       let c = Vec2.clamp v ~min:mn ~max:mx in
       vec2_eq (Vec2.clamp c ~min:mn ~max:mx) c)

let prop_vec2_reflect_length_preserved =
  QCheck.Test.make ~name:"Vec2 reflect preserves length" ~count:1_000
    arb_vec2
    (fun v ->
       let n = Vec2.normalize (Vec2.create 0.0 1.0) in
       float_eq (Vec2.length (Vec2.reflect v n)) (Vec2.length v))

let prop_vec2_project_onto_axis =
  QCheck.Test.make ~name:"Vec2 project result is parallel to onto" ~count:1_000
    (QCheck.pair arb_vec2 (QCheck.make gen_nonzero_float))
    (fun (v, s) ->
       let onto = Vec2.create s 0.0 in
       let p = Vec2.project v ~onto in
       float_eq p.Vec2.y 0.0)

(* ------------------------------------------------------------------ *)
(* Vec2i properties                                                     *)
(* ------------------------------------------------------------------ *)

let gen_vec2i =
  QCheck.Gen.(map2 Vec2i.create (int_range (-100) 100) (int_range (-100) 100))

let arb_vec2i = QCheck.make gen_vec2i

let prop_vec2i_add_commutative =
  QCheck.Test.make ~name:"Vec2i add commutative" ~count:1_000
    (QCheck.pair arb_vec2i arb_vec2i)
    (fun (a, b) ->
       let r1 = Vec2i.add a b and r2 = Vec2i.add b a in
       r1.x = r2.x && r1.y = r2.y)

let prop_vec2i_to_vec2_floor_roundtrip =
  QCheck.Test.make ~name:"Vec2i to_vec2 then of_vec2_floor round-trips integers" ~count:1_000
    arb_vec2i
    (fun v ->
       let rt = Vec2i.of_vec2_floor (Vec2i.to_vec2 v) in
       rt.x = v.x && rt.y = v.y)

(* ------------------------------------------------------------------ *)
(* Circle properties                                                    *)
(* ------------------------------------------------------------------ *)

let gen_circle =
  QCheck.Gen.(map2
    (fun center r -> Circle.create center (Float.abs r +. 0.1))
    gen_vec2 gen_float)

let arb_circle = QCheck.make gen_circle

let prop_circle_intersects_symmetric =
  QCheck.Test.make ~name:"Circle intersects is symmetric" ~count:1_000
    (QCheck.pair arb_circle arb_circle)
    (fun (a, b) -> Circle.intersects a b = Circle.intersects b a)

let prop_circle_contains_center =
  QCheck.Test.make ~name:"Circle always contains its own center" ~count:1_000
    arb_circle
    (fun c -> Circle.contains_point c c.Circle.center)

(* ------------------------------------------------------------------ *)
(* Rect properties                                                      *)
(* ------------------------------------------------------------------ *)

let gen_rect =
  QCheck.Gen.(map (fun (x, y, w, h) ->
    Rect.create x y (Float.abs w +. 0.1) (Float.abs h +. 0.1))
    (quad gen_float gen_float gen_float gen_float))

let arb_rect = QCheck.make gen_rect

let prop_rect_intersects_symmetric =
  QCheck.Test.make ~name:"Rect intersects is symmetric" ~count:1_000
    (QCheck.pair arb_rect arb_rect)
    (fun (a, b) -> Rect.intersects a b = Rect.intersects b a)

let prop_rect_merge_commutative =
  QCheck.Test.make ~name:"Rect merge is commutative" ~count:1_000
    (QCheck.pair arb_rect arb_rect)
    (fun (a, b) ->
       let m1 = Rect.merge a b and m2 = Rect.merge b a in
       float_eq m1.x m2.x && float_eq m1.y m2.y &&
       float_eq m1.w m2.w && float_eq m1.h m2.h)

let prop_rect_merge_contains_both =
  QCheck.Test.make ~name:"Rect merge contains both input rects" ~count:1_000
    (QCheck.pair arb_rect arb_rect)
    (fun (a, b) ->
       let m = Rect.merge a b in
       m.x <= a.x && m.y <= a.y &&
       m.x <= b.x && m.y <= b.y &&
       m.x +. m.w >= a.x +. a.w -. eps &&
       m.y +. m.h >= a.y +. a.h -. eps &&
       m.x +. m.w >= b.x +. b.w -. eps &&
       m.y +. m.h >= b.y +. b.h -. eps)

let prop_rect_of_min_max_roundtrip =
  QCheck.Test.make ~name:"Rect of_min_max/min/max round-trip" ~count:1_000
    arb_rect
    (fun r ->
       let r2 = Rect.of_min_max (Rect.min r) (Rect.max r) in
       float_eq r.x r2.x && float_eq r.y r2.y &&
       float_eq r.w r2.w && float_eq r.h r2.h)

let prop_rect_intersection_consistent_with_contains =
  QCheck.Test.make ~name:"Rect intersection consistent with contains_point" ~count:1_000
    (QCheck.pair arb_rect arb_rect)
    (fun (a, b) ->
       match Rect.intersection a b with
       | None    -> not (Rect.intersects a b)
       | Some _i -> Rect.intersects a b)

(* ------------------------------------------------------------------ *)
(* Transform2D properties                                               *)
(* ------------------------------------------------------------------ *)

let angle_eq a b =
  let two_pi = 2.0 *. Float.pi in
  let diff = mod_float (a -. b) two_pi in
  let diff = if diff > Float.pi then diff -. two_pi
             else if diff <= -. Float.pi then diff +. two_pi
             else diff in
  Float.abs diff < eps

let prop_transform_compose_identity_left =
  QCheck.Test.make ~name:"Transform2D compose identity left" ~count:1_000
    arb_transform
    (fun t -> transform_eq (Transform2D.compose Transform2D.identity t) t)

let prop_transform_compose_identity_right =
  QCheck.Test.make ~name:"Transform2D compose identity right" ~count:1_000
    arb_transform
    (fun t -> transform_eq (Transform2D.compose t Transform2D.identity) t)

let prop_transform_inverse =
  QCheck.Test.make ~name:"Transform2D compose t (inverse t) ≈ identity" ~count:1_000
    arb_transform
    (fun t ->
       transform_eq
         (Transform2D.compose t (Transform2D.inverse t))
         Transform2D.identity)

let prop_transform_apply_point_compose =
  (* apply_point (compose parent child) p = apply_point parent (apply_point child p)
     holds only for uniform scale — non-uniform scale breaks the TRS composition law
     (same limitation as Unity, Godot, and Bevy). *)
  let gen_uniform =
    QCheck.Gen.(map3
      (fun pos rot s ->
        Transform2D.create ~position:pos ~rotation:rot
          ~scale:(Vec2.create s s))
      gen_vec2 gen_float gen_nonzero_float)
  in
  QCheck.Test.make ~name:"Transform2D apply_point consistent with compose (uniform scale)" ~count:1_000
    (QCheck.triple (QCheck.make gen_uniform) (QCheck.make gen_uniform) arb_vec2)
    (fun (parent, child, p) ->
       let composed    = Transform2D.compose parent child in
       let via_compose = Transform2D.apply_point composed p in
       let via_chain   = Transform2D.apply_point parent
                           (Transform2D.apply_point child p) in
       vec2_eq via_compose via_chain)

let prop_transform_lerp_at_zero =
  QCheck.Test.make ~name:"Transform2D lerp t=0 returns a" ~count:1_000
    (QCheck.pair arb_transform arb_transform)
    (fun (a, b) -> transform_eq (Transform2D.lerp a b 0.0) a)

let prop_transform_lerp_at_one =
  (* position and scale use float equality; rotation uses angle equivalence
     because lerp uses lerp_angle which may shift by 2π at the ±π boundary *)
  QCheck.Test.make ~name:"Transform2D lerp t=1 angle-equivalent to b" ~count:1_000
    (QCheck.pair arb_transform arb_transform)
    (fun (a, b) ->
       let r = Transform2D.lerp a b 1.0 in
       vec2_eq r.Transform2D.position b.Transform2D.position &&
       angle_eq r.Transform2D.rotation b.Transform2D.rotation &&
       vec2_eq r.Transform2D.scale b.Transform2D.scale)

let prop_lerp_angle_short_path =
  QCheck.Test.make ~name:"lerp_angle always takes the short arc" ~count:1_000
    (QCheck.pair
      (QCheck.make QCheck.Gen.(float_range (-.Float.pi) Float.pi))
      (QCheck.make QCheck.Gen.(float_range (-.Float.pi) Float.pi)))
    (fun (a, b) ->
       let mid = Transform2D.lerp_angle a b 0.5 in
       (* midpoint of shortest arc is at most π/2 away from both endpoints *)
       let da = Float.abs (mod_float (mid -. a) (2.0 *. Float.pi)) in
       let da = if da > Float.pi then 2.0 *. Float.pi -. da else da in
       da <= Float.pi /. 2.0 +. eps)

let prop_lerp_angle_endpoints =
  (* t=0 returns a exactly (float); t=1 is angle-equivalent to b (may differ
     by 2π when crossing the ±π boundary) *)
  QCheck.Test.make ~name:"lerp_angle t=0 returns a, t=1 angle-equivalent to b" ~count:1_000
    (QCheck.pair
      (QCheck.make QCheck.Gen.(float_range (-.Float.pi) Float.pi))
      (QCheck.make QCheck.Gen.(float_range (-.Float.pi) Float.pi)))
    (fun (a, b) ->
       float_eq (Transform2D.lerp_angle a b 0.0) a &&
       angle_eq (Transform2D.lerp_angle a b 1.0) b)


(* ------------------------------------------------------------------ *)
(* Registration                                                         *)
(* ------------------------------------------------------------------ *)

let tests =
  List.map QCheck_alcotest.to_alcotest [
    prop_vec2_add_commutative;
    prop_vec2_perpendicular_double;
    prop_vec2_perpendicular_length;
    prop_vec2_clamp_idempotent;
    prop_vec2_reflect_length_preserved;
    prop_vec2_project_onto_axis;
    prop_vec2i_add_commutative;
    prop_vec2i_to_vec2_floor_roundtrip;
    prop_circle_intersects_symmetric;
    prop_circle_contains_center;
    prop_vec2_add_associative;
    prop_vec2_mul_div_roundtrip;
    prop_vec2_length_sq_eq_length_squared;
    prop_vec2_normalize_unit_length;
    prop_vec2_from_angle_angle_roundtrip;
    prop_vec2_lerp_at_zero;
    prop_vec2_lerp_at_one;
    prop_rect_intersects_symmetric;
    prop_rect_merge_commutative;
    prop_rect_merge_contains_both;
    prop_rect_of_min_max_roundtrip;
    prop_rect_intersection_consistent_with_contains;
    prop_transform_compose_identity_left;
    prop_transform_compose_identity_right;
    prop_transform_inverse;
    prop_transform_apply_point_compose;
    prop_transform_lerp_at_zero;
    prop_transform_lerp_at_one;
    prop_lerp_angle_short_path;
    prop_lerp_angle_endpoints;
  ]
