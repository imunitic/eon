open Eon_engine.Math

let eps = 1e-9

let check_float ~msg a b =
  Alcotest.(check (float eps)) msg a b

let check_vec2 ~msg (a : Vec2.t) (b : Vec2.t) =
  check_float ~msg:(msg ^ ".x") a.x b.x;
  check_float ~msg:(msg ^ ".y") a.y b.y

let check_transform ~msg (a : Transform2D.t) (b : Transform2D.t) =
  check_vec2  ~msg:(msg ^ ".position") a.position b.position;
  check_float ~msg:(msg ^ ".rotation") a.rotation b.rotation;
  check_vec2  ~msg:(msg ^ ".scale")    a.scale    b.scale

(* ------------------------------------------------------------------ *)
(* Vec2                                                                 *)
(* ------------------------------------------------------------------ *)

let test_vec2_zero () =
  check_vec2 ~msg:"zero" Vec2.zero { x = 0.0; y = 0.0 }

let test_vec2_one () =
  check_vec2 ~msg:"one" Vec2.one { x = 1.0; y = 1.0 }

let test_vec2_create () =
  check_vec2 ~msg:"create" (Vec2.create 3.0 4.0) { x = 3.0; y = 4.0 }

let test_vec2_add () =
  let a = Vec2.create 1.0 2.0 and b = Vec2.create 3.0 4.0 in
  check_vec2 ~msg:"add" (Vec2.add a b) (Vec2.create 4.0 6.0)

let test_vec2_sub () =
  let a = Vec2.create 5.0 3.0 and b = Vec2.create 2.0 1.0 in
  check_vec2 ~msg:"sub" (Vec2.sub a b) (Vec2.create 3.0 2.0)

let test_vec2_mul () =
  check_vec2 ~msg:"mul" (Vec2.mul (Vec2.create 2.0 3.0) 4.0) (Vec2.create 8.0 12.0)

let test_vec2_div () =
  check_vec2 ~msg:"div" (Vec2.div (Vec2.create 8.0 12.0) 4.0) (Vec2.create 2.0 3.0)

let test_vec2_neg () =
  check_vec2 ~msg:"neg" (Vec2.neg (Vec2.create 1.0 (-2.0))) (Vec2.create (-1.0) 2.0)

let test_vec2_mul_v () =
  let a = Vec2.create 2.0 3.0 and b = Vec2.create 4.0 5.0 in
  check_vec2 ~msg:"mul_v" (Vec2.mul_v a b) (Vec2.create 8.0 15.0)

let test_vec2_dot () =
  let a = Vec2.create 1.0 2.0 and b = Vec2.create 3.0 4.0 in
  check_float ~msg:"dot" (Vec2.dot a b) 11.0

let test_vec2_length () =
  check_float ~msg:"length 3-4-5" (Vec2.length (Vec2.create 3.0 4.0)) 5.0

let test_vec2_length_sq () =
  check_float ~msg:"length_sq" (Vec2.length_sq (Vec2.create 3.0 4.0)) 25.0

let test_vec2_normalize () =
  let n = Vec2.normalize (Vec2.create 3.0 4.0) in
  check_float ~msg:"normalize length" (Vec2.length n) 1.0

let test_vec2_normalize_zero () =
  let n = Vec2.normalize Vec2.zero in
  check_vec2 ~msg:"normalize zero unchanged" n Vec2.zero

let test_vec2_distance () =
  let a = Vec2.create 0.0 0.0 and b = Vec2.create 3.0 4.0 in
  check_float ~msg:"distance" (Vec2.distance a b) 5.0

let test_vec2_perpendicular () =
  check_vec2 ~msg:"perp of (1,0)" (Vec2.perpendicular (Vec2.create 1.0 0.0)) (Vec2.create 0.0 1.0);
  check_vec2 ~msg:"perp of (0,1)" (Vec2.perpendicular (Vec2.create 0.0 1.0)) (Vec2.create (-1.0) 0.0)

let test_vec2_rotate_quarter () =
  let v = Vec2.rotate (Vec2.create 1.0 0.0) (Float.pi /. 2.0) in
  check_float ~msg:"rotate quarter x" v.x 0.0;
  check_float ~msg:"rotate quarter y" v.y 1.0

let test_vec2_from_angle_angle () =
  let a = 1.2 in
  check_float ~msg:"from_angle/angle round-trip" (Vec2.angle (Vec2.from_angle a)) a

let test_vec2_lerp_endpoints () =
  let a = Vec2.create 0.0 0.0 and b = Vec2.create 10.0 20.0 in
  check_vec2 ~msg:"lerp t=0" (Vec2.lerp a b 0.0) a;
  check_vec2 ~msg:"lerp t=1" (Vec2.lerp a b 1.0) b

(* ------------------------------------------------------------------ *)
(* Rect                                                                 *)
(* ------------------------------------------------------------------ *)

let test_rect_create () =
  let r = Rect.create 1.0 2.0 3.0 4.0 in
  Alcotest.(check (float eps)) "x" r.x 1.0;
  Alcotest.(check (float eps)) "y" r.y 2.0;
  Alcotest.(check (float eps)) "w" r.w 3.0;
  Alcotest.(check (float eps)) "h" r.h 4.0

let test_rect_min_max () =
  let r = Rect.create 1.0 2.0 3.0 4.0 in
  check_vec2 ~msg:"min" (Rect.min r) (Vec2.create 1.0 2.0);
  check_vec2 ~msg:"max" (Rect.max r) (Vec2.create 4.0 6.0)

let test_rect_center () =
  let r = Rect.create 0.0 0.0 4.0 6.0 in
  check_vec2 ~msg:"center" (Rect.center r) (Vec2.create 2.0 3.0)

let test_rect_of_min_max () =
  let r = Rect.of_min_max (Vec2.create 1.0 2.0) (Vec2.create 4.0 6.0) in
  Alcotest.(check (float eps)) "x" r.x 1.0;
  Alcotest.(check (float eps)) "y" r.y 2.0;
  Alcotest.(check (float eps)) "w" r.w 3.0;
  Alcotest.(check (float eps)) "h" r.h 4.0

let test_rect_contains_point () =
  let r = Rect.create 0.0 0.0 10.0 10.0 in
  Alcotest.(check bool) "inside" true  (Rect.contains_point r (Vec2.create 5.0 5.0));
  Alcotest.(check bool) "outside" false (Rect.contains_point r (Vec2.create 15.0 5.0))

let test_rect_intersects () =
  let a = Rect.create 0.0 0.0 5.0 5.0 in
  let b = Rect.create 3.0 3.0 5.0 5.0 in
  let c = Rect.create 10.0 10.0 2.0 2.0 in
  Alcotest.(check bool) "overlapping" true  (Rect.intersects a b);
  Alcotest.(check bool) "separate"    false (Rect.intersects a c)

let test_rect_intersection_some () =
  let a = Rect.create 0.0 0.0 5.0 5.0 in
  let b = Rect.create 3.0 3.0 5.0 5.0 in
  match Rect.intersection a b with
  | None -> Alcotest.fail "expected Some"
  | Some r ->
    Alcotest.(check (float eps)) "x" r.x 3.0;
    Alcotest.(check (float eps)) "y" r.y 3.0;
    Alcotest.(check (float eps)) "w" r.w 2.0;
    Alcotest.(check (float eps)) "h" r.h 2.0

let test_rect_intersection_none () =
  let a = Rect.create 0.0 0.0 5.0 5.0 in
  let b = Rect.create 10.0 10.0 2.0 2.0 in
  Alcotest.(check (option (Alcotest.testable (fun _ _ -> ()) (=)))) "none" None (Rect.intersection a b)

let test_rect_translate () =
  let r = Rect.create 1.0 2.0 3.0 4.0 in
  let r' = Rect.translate r (Vec2.create 10.0 20.0) in
  Alcotest.(check (float eps)) "x" r'.x 11.0;
  Alcotest.(check (float eps)) "y" r'.y 22.0;
  Alcotest.(check (float eps)) "w" r'.w 3.0;
  Alcotest.(check (float eps)) "h" r'.h 4.0

let test_rect_expand () =
  let r = Rect.expand (Rect.create 1.0 2.0 4.0 6.0) 1.0 in
  Alcotest.(check (float eps)) "x" r.x 0.0;
  Alcotest.(check (float eps)) "y" r.y 1.0;
  Alcotest.(check (float eps)) "w" r.w 6.0;
  Alcotest.(check (float eps)) "h" r.h 8.0

let test_rect_merge () =
  let a = Rect.create 0.0 0.0 3.0 3.0 in
  let b = Rect.create 2.0 2.0 3.0 3.0 in
  let m = Rect.merge a b in
  Alcotest.(check (float eps)) "x" m.x 0.0;
  Alcotest.(check (float eps)) "y" m.y 0.0;
  Alcotest.(check (float eps)) "w" m.w 5.0;
  Alcotest.(check (float eps)) "h" m.h 5.0

(* ------------------------------------------------------------------ *)
(* Vec2 — new functions                                                 *)
(* ------------------------------------------------------------------ *)

let test_vec2_clamp () =
  let mn = Vec2.create 0.0 0.0 and mx = Vec2.create 5.0 5.0 in
  check_vec2 ~msg:"clamp inside"   (Vec2.clamp (Vec2.create 2.0 3.0) ~min:mn ~max:mx) (Vec2.create 2.0 3.0);
  check_vec2 ~msg:"clamp below"    (Vec2.clamp (Vec2.create (-1.0) (-2.0)) ~min:mn ~max:mx) mn;
  check_vec2 ~msg:"clamp above"    (Vec2.clamp (Vec2.create 10.0 10.0) ~min:mn ~max:mx) mx

let test_vec2_reflect () =
  let v = Vec2.create 1.0 (-1.0) in
  let n = Vec2.create 0.0 1.0 in
  check_vec2 ~msg:"reflect off horizontal surface" (Vec2.reflect v n) (Vec2.create 1.0 1.0)

let test_vec2_project () =
  let v    = Vec2.create 3.0 4.0 in
  let onto = Vec2.create 1.0 0.0 in
  check_vec2 ~msg:"project onto x axis" (Vec2.project v ~onto) (Vec2.create 3.0 0.0)

(* ------------------------------------------------------------------ *)
(* Vec2i                                                                *)
(* ------------------------------------------------------------------ *)

let test_vec2i_create () =
  let v = Vec2i.create 3 4 in
  Alcotest.(check int) "x" v.x 3;
  Alcotest.(check int) "y" v.y 4

let test_vec2i_add () =
  check_vec2 ~msg:"add"
    (Vec2i.to_vec2 (Vec2i.add (Vec2i.create 1 2) (Vec2i.create 3 4)))
    (Vec2.create 4.0 6.0)

let test_vec2i_to_vec2 () =
  check_vec2 ~msg:"to_vec2" (Vec2i.to_vec2 (Vec2i.create 3 4)) (Vec2.create 3.0 4.0)

let test_vec2i_of_vec2_floor () =
  let v = Vec2i.of_vec2_floor (Vec2.create 2.9 3.1) in
  Alcotest.(check int) "x" v.x 2;
  Alcotest.(check int) "y" v.y 3

let test_vec2i_of_vec2_round () =
  let v = Vec2i.of_vec2_round (Vec2.create 2.5 3.4) in
  Alcotest.(check int) "x" v.x 3;
  Alcotest.(check int) "y" v.y 3

let test_vec2i_of_vec2_ceil () =
  let v = Vec2i.of_vec2_ceil (Vec2.create 2.1 3.0) in
  Alcotest.(check int) "x" v.x 3;
  Alcotest.(check int) "y" v.y 3

(* ------------------------------------------------------------------ *)
(* Rect — new functions                                                 *)
(* ------------------------------------------------------------------ *)

let test_rect_scale () =
  let r = Rect.scale (Rect.create 1.0 2.0 4.0 6.0) 2.0 in
  Alcotest.(check (float eps)) "x" r.x 2.0;
  Alcotest.(check (float eps)) "y" r.y 4.0;
  Alcotest.(check (float eps)) "w" r.w 8.0;
  Alcotest.(check (float eps)) "h" r.h 12.0

(* ------------------------------------------------------------------ *)
(* Circle                                                               *)
(* ------------------------------------------------------------------ *)

let test_circle_contains_point () =
  let c = Circle.create (Vec2.create 0.0 0.0) 5.0 in
  Alcotest.(check bool) "inside"  true  (Circle.contains_point c (Vec2.create 3.0 4.0));
  Alcotest.(check bool) "outside" false (Circle.contains_point c (Vec2.create 4.0 4.0))

let test_circle_intersects () =
  let a = Circle.create (Vec2.create 0.0 0.0) 3.0 in
  let b = Circle.create (Vec2.create 4.0 0.0) 2.0 in
  let c = Circle.create (Vec2.create 10.0 0.0) 1.0 in
  Alcotest.(check bool) "overlapping" true  (Circle.intersects a b);
  Alcotest.(check bool) "separate"    false (Circle.intersects a c)

let test_circle_intersects_rect () =
  let c = Circle.create (Vec2.create 0.0 0.0) 5.0 in
  let r_overlap = Rect.create 3.0 3.0 4.0 4.0 in
  let r_far     = Rect.create 10.0 10.0 2.0 2.0 in
  Alcotest.(check bool) "overlapping" true  (Circle.intersects_rect c r_overlap);
  Alcotest.(check bool) "separate"    false (Circle.intersects_rect c r_far)

(* ------------------------------------------------------------------ *)
(* Transform2D                                                          *)
(* ------------------------------------------------------------------ *)

let test_transform_identity () =
  check_transform ~msg:"identity" Transform2D.identity
    { position = Vec2.zero; rotation = 0.0; scale = Vec2.one }

let test_transform_compose_identity_left () =
  let t = Transform2D.create
      ~position:(Vec2.create 1.0 2.0)
      ~rotation:0.5
      ~scale:(Vec2.create 2.0 3.0) in
  let result = Transform2D.compose Transform2D.identity t in
  check_transform ~msg:"identity left" result t

let test_transform_compose_identity_right () =
  let t = Transform2D.create
      ~position:(Vec2.create 1.0 2.0)
      ~rotation:0.5
      ~scale:(Vec2.create 2.0 3.0) in
  let result = Transform2D.compose t Transform2D.identity in
  check_transform ~msg:"identity right" result t

let test_transform_inverse () =
  let t = Transform2D.create
      ~position:(Vec2.create 3.0 4.0)
      ~rotation:1.0
      ~scale:(Vec2.create 2.0 2.0) in
  let result = Transform2D.compose t (Transform2D.inverse t) in
  check_transform ~msg:"t compose inverse ≈ identity" result Transform2D.identity

let test_transform_apply_point_identity () =
  let p = Vec2.create 3.0 7.0 in
  check_vec2 ~msg:"apply identity" (Transform2D.apply_point Transform2D.identity p) p

let test_transform_lerp_endpoints () =
  let a = Transform2D.create ~position:(Vec2.create 0.0 0.0) ~rotation:0.0 ~scale:Vec2.one in
  let b = Transform2D.create ~position:(Vec2.create 10.0 0.0) ~rotation:1.0 ~scale:(Vec2.create 2.0 2.0) in
  check_transform ~msg:"lerp t=0" (Transform2D.lerp a b 0.0) a;
  (* t=1: position and scale are float-equal; rotation is angle-equivalent *)
  let r = Transform2D.lerp a b 1.0 in
  check_vec2  ~msg:"lerp t=1 position" r.Transform2D.position b.Transform2D.position;
  check_float ~msg:"lerp t=1 rotation" r.Transform2D.rotation b.Transform2D.rotation;
  check_vec2  ~msg:"lerp t=1 scale"    r.Transform2D.scale    b.Transform2D.scale

let test_transform_lerp_short_rotation_path () =
  let a = Transform2D.create ~position:Vec2.zero ~rotation:3.1    ~scale:Vec2.one in
  let b = Transform2D.create ~position:Vec2.zero ~rotation:(-3.1) ~scale:Vec2.one in
  let mid = Transform2D.lerp a b 0.5 in
  Alcotest.(check bool) "short path rotation" true (Float.abs mid.Transform2D.rotation > 2.0)

let test_lerp_angle_short_path () =
  (* 3.1 and -3.1 are on opposite sides of ±π — short path crosses the boundary *)
  let result = Transform2D.lerp_angle 3.1 (-3.1) 0.5 in
  (* short arc midpoint is near ±π, not near 0 *)
  Alcotest.(check bool) "short path" true (Float.abs result > 2.0)

let test_lerp_angle_endpoints () =
  check_float ~msg:"t=0" (Transform2D.lerp_angle 1.0 2.0 0.0) 1.0;
  check_float ~msg:"t=1" (Transform2D.lerp_angle 1.0 2.0 1.0) 2.0


(* ------------------------------------------------------------------ *)
(* Registration                                                         *)
(* ------------------------------------------------------------------ *)

let tests = [
  "Vec2 zero",                `Quick, test_vec2_zero;
  "Vec2 one",                 `Quick, test_vec2_one;
  "Vec2 create",              `Quick, test_vec2_create;
  "Vec2 add",                 `Quick, test_vec2_add;
  "Vec2 sub",                 `Quick, test_vec2_sub;
  "Vec2 mul",                 `Quick, test_vec2_mul;
  "Vec2 div",                 `Quick, test_vec2_div;
  "Vec2 neg",                 `Quick, test_vec2_neg;
  "Vec2 mul_v",               `Quick, test_vec2_mul_v;
  "Vec2 dot",                 `Quick, test_vec2_dot;
  "Vec2 length",              `Quick, test_vec2_length;
  "Vec2 length_sq",           `Quick, test_vec2_length_sq;
  "Vec2 normalize",           `Quick, test_vec2_normalize;
  "Vec2 normalize zero",      `Quick, test_vec2_normalize_zero;
  "Vec2 distance",            `Quick, test_vec2_distance;
  "Vec2 perpendicular",        `Quick, test_vec2_perpendicular;
  "Vec2 rotate quarter turn", `Quick, test_vec2_rotate_quarter;
  "Vec2 from_angle/angle",    `Quick, test_vec2_from_angle_angle;
  "Vec2 lerp endpoints",      `Quick, test_vec2_lerp_endpoints;
  "Rect create",              `Quick, test_rect_create;
  "Rect min/max",             `Quick, test_rect_min_max;
  "Rect center",              `Quick, test_rect_center;
  "Rect of_min_max",          `Quick, test_rect_of_min_max;
  "Rect contains_point",      `Quick, test_rect_contains_point;
  "Rect intersects",          `Quick, test_rect_intersects;
  "Rect intersection Some",   `Quick, test_rect_intersection_some;
  "Rect intersection None",   `Quick, test_rect_intersection_none;
  "Rect translate",           `Quick, test_rect_translate;
  "Rect expand",              `Quick, test_rect_expand;
  "Rect merge",               `Quick, test_rect_merge;
  "Rect scale",               `Quick, test_rect_scale;
  "Vec2 clamp",               `Quick, test_vec2_clamp;
  "Vec2 reflect",             `Quick, test_vec2_reflect;
  "Vec2 project",             `Quick, test_vec2_project;
  "Vec2i create",             `Quick, test_vec2i_create;
  "Vec2i add",                `Quick, test_vec2i_add;
  "Vec2i to_vec2",            `Quick, test_vec2i_to_vec2;
  "Vec2i of_vec2_floor",      `Quick, test_vec2i_of_vec2_floor;
  "Vec2i of_vec2_round",      `Quick, test_vec2i_of_vec2_round;
  "Vec2i of_vec2_ceil",       `Quick, test_vec2i_of_vec2_ceil;
  "Circle contains_point",    `Quick, test_circle_contains_point;
  "Circle intersects",        `Quick, test_circle_intersects;
  "Circle intersects_rect",   `Quick, test_circle_intersects_rect;
  "Transform2D identity",                  `Quick, test_transform_identity;
  "Transform2D compose identity left",     `Quick, test_transform_compose_identity_left;
  "Transform2D compose identity right",    `Quick, test_transform_compose_identity_right;
  "Transform2D inverse",                   `Quick, test_transform_inverse;
  "Transform2D apply_point identity",      `Quick, test_transform_apply_point_identity;
  "Transform2D lerp endpoints",              `Quick, test_transform_lerp_endpoints;
  "Transform2D lerp short rotation path",   `Quick, test_transform_lerp_short_rotation_path;
  "Transform2D lerp_angle short path",      `Quick, test_lerp_angle_short_path;
  "Transform2D lerp_angle endpoints",       `Quick, test_lerp_angle_endpoints;
]
