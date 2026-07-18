(* Companion example for docs/eon_engine chapter: Math types. *)

open Eon_engine
open Eon_engine.Math

let vec2_example () =
  let pos    = Vec2.create 100.0 200.0 in
  let vel    = Vec2.create 1.5 (-0.5) in
  let target = Vec2.create 300.0 400.0 in
  let radius = 50.0 in
  let dt     = 0.016 in

  let zero   = Vec2.zero in
  let unit_x = Vec2.from_angle 0.0 in

  let next_pos = Vec2.add pos (Vec2.mul vel dt) in

  let dist  = Vec2.distance pos target in
  let dir   = Vec2.normalize (Vec2.sub target pos) in
  let speed = Vec2.length vel in

  let in_range = Vec2.distance_sq pos target <= radius *. radius in

  assert (zero.x = 0.0 && zero.y = 0.0);
  assert (Float.abs (unit_x.x -. 1.0) < 1e-9);
  assert (next_pos.x > pos.x);
  assert (dist > 0.0);
  assert (Float.abs (Vec2.length dir -. 1.0) < 1e-9);
  assert (speed > 0.0);
  assert (not in_range)

let rotation_example () =
  let vel             = Vec2.create 1.5 (-0.5) in
  let dir             = Vec2.normalize (Vec2.create 1.0 1.0) in
  let player_rotation = Float.pi /. 4.0 in

  let rotated    = Vec2.rotate vel (Float.pi /. 4.0) in
  let facing     = Vec2.angle dir in
  let aim_dir    = Vec2.from_angle player_rotation in
  let strafe_dir = Vec2.perpendicular dir in

  assert (Float.abs (Vec2.length rotated -. Vec2.length vel) < 1e-9);
  assert (facing > 0.0);
  assert (Float.abs (Vec2.length aim_dir -. 1.0) < 1e-9);
  assert (Float.abs (Vec2.dot dir strafe_dir) < 1e-9)

let reflect_project_clamp_example () =
  let vel            = Vec2.create 1.0 (-1.0) in
  let pos            = Vec2.create 320.0 240.0 in
  let surface_normal = Vec2.create 0.0 1.0 in
  let slope_dir      = Vec2.normalize (Vec2.create 1.0 0.5) in
  let world_w        = 640.0 in
  let world_h        = 480.0 in

  let bounced_vel = Vec2.reflect vel surface_normal in
  let along_slope = Vec2.project vel ~onto:slope_dir in
  let clamped_pos = Vec2.clamp pos
    ~min:(Vec2.create 0.0 0.0)
    ~max:(Vec2.create world_w world_h)
  in

  assert (bounced_vel.y > 0.0);
  assert (along_slope.x > 0.0);
  assert (clamped_pos.x = pos.x && clamped_pos.y = pos.y)

let vec2i_example () =
  let world_pos = Vec2.create 2.9 3.7 in
  let tile_pos = Vec2i.of_vec2_floor world_pos in
  assert (tile_pos.Vec2i.x = 2 && tile_pos.Vec2i.y = 3);

  let world_corner = Vec2i.to_vec2 tile_pos in
  assert (world_corner.x = 2.0 && world_corner.y = 3.0);

  let right = Vec2i.add tile_pos (Vec2i.create 1 0) in
  let below = Vec2i.add tile_pos (Vec2i.create 0 1) in
  assert (right.Vec2i.x = 3);
  assert (below.Vec2i.y = 4)

let rect_example () =
  let player_bounds = Rect.create 10.0 10.0 32.0 64.0 in
  let enemy_bounds  = Rect.create 30.0 20.0 32.0 64.0 in
  let ui_panel      = Rect.create 0.0 0.0 200.0 50.0 in
  let button_rect   = Rect.create 10.0 10.0 80.0 30.0 in
  let mouse_pos     = Vec2.create 50.0 25.0 in
  let view_rect     = Rect.create 0.0 0.0 640.0 480.0 in
  let zoom_factor   = 1.5 in
  let positions     = [ Vec2.create 10.0 20.0; Vec2.create 50.0 80.0; Vec2.create 30.0 10.0 ] in

  let hit     = Rect.intersects player_bounds enemy_bounds in
  let clicked = Rect.contains_point ui_panel mouse_pos in
  let overlap = Rect.intersection player_bounds enemy_bounds in

  let aabb = List.fold_left
    (fun acc (pos : Vec2.t) -> Rect.merge acc (Rect.create pos.x pos.y 0.0 0.0))
    (Rect.create Float.max_float Float.max_float 0.0 0.0)
    positions
  in

  let zoomed = Rect.scale view_rect zoom_factor in
  let padded = Rect.expand button_rect 4.0 in

  assert hit;
  assert clicked;
  assert (Option.is_some overlap);
  assert (aabb.Rect.w > 0.0);
  assert (zoomed.Rect.w > view_rect.Rect.w);
  assert (padded.Rect.w > button_rect.Rect.w)

let circle_example () =
  let entity_pos    = Vec2.create 100.0 100.0 in
  let player_pos    = Vec2.create 105.0 105.0 in
  let player_hitbox = Circle.create (Vec2.create 100.0 100.0) 16.0 in
  let enemy_hitbox  = Circle.create (Vec2.create 120.0 100.0) 16.0 in
  let pickup_radius = Circle.create entity_pos 24.0 in
  let explosion     = Circle.create (Vec2.create 200.0 200.0) 80.0 in
  let trigger_zone  = Rect.create 180.0 180.0 100.0 100.0 in

  let hit_enemy  = Circle.intersects player_hitbox enemy_hitbox in
  let in_trigger = Circle.intersects_rect explosion trigger_zone in
  let picked_up  = Circle.contains_point pickup_radius player_pos in

  assert hit_enemy;
  assert in_trigger;
  assert picked_up

let collision_manifold_example () =
  let a = Circle.create (Vec2.create 0.0 0.0) 20.0 in
  let b = Circle.create (Vec2.create 25.0 0.0) 10.0 in

  match Circle.collide a b with
  | None -> assert false
  | Some { Manifold.normal; depth } ->
    assert (depth > 0.0);
    let separation = Vec2.mul normal depth in
    assert (separation.x > 0.0)

let transform2d_example () =
  let parent = Transform2D.create
    ~position:(Vec2.create 100.0 200.0)
    ~rotation:0.5
    ~scale:Vec2.one
  in
  let child_local = Transform2D.create
    ~position:(Vec2.create 20.0 0.0)
    ~rotation:0.0
    ~scale:Vec2.one
  in

  let child_world = Transform2D.compose parent child_local in

  let local_point = Vec2.create 5.0 0.0 in
  let world_pt    = Transform2D.apply_point parent local_point in
  let back_to_local = Transform2D.apply_point (Transform2D.inverse parent) world_pt in

  assert (child_world.Transform2D.position.x <> parent.Transform2D.position.x);
  assert (Float.abs (back_to_local.x -. local_point.x) < 1e-6);
  assert (Float.abs (back_to_local.y -. local_point.y) < 1e-6)

let interpolation_example () =
  let current_cam       = Transform2D.create ~position:(Vec2.create 0.0 0.0)   ~rotation:0.0  ~scale:Vec2.one in
  let target_cam        = Transform2D.create ~position:(Vec2.create 200.0 50.0) ~rotation:0.1  ~scale:Vec2.one in
  let current_transform = Transform2D.create ~position:(Vec2.create 10.0 10.0) ~rotation:3.1  ~scale:Vec2.one in
  let target_transform  = Transform2D.create ~position:(Vec2.create 50.0 50.0) ~rotation:(-3.1) ~scale:Vec2.one in
  let stiffness  = 5.0 in
  let speed      = 2.0 in
  let turn_speed = 3.0 in
  let dt         = 0.016 in
  let current_angle = 3.1 in
  let target_angle  = -3.1 in

  let smoothed = Transform2D.lerp current_cam target_cam (1.0 -. Float.exp (-. stiffness *. dt)) in
  let rotated  = Transform2D.lerp current_transform target_transform (speed *. dt) in
  let facing   = Transform2D.lerp_angle current_angle target_angle (turn_speed *. dt) in

  assert (smoothed.Transform2D.position.x > current_cam.Transform2D.position.x);
  assert (rotated.Transform2D.rotation <> current_transform.Transform2D.rotation);
  assert (Float.abs facing > 3.0)

(* Building Math shapes from Collider + World_transform. Both are
   Components.World_transform / Components.Collider — the bare, unqualified
   names World_transform / Collider do not exist at this scope. *)
let circle_of (wt : Components.World_transform.t) (radius : float) =
  Math.Circle.create (Math.Vec2.create wt.position.x wt.position.y) radius

let rect_of (wt : Components.World_transform.t) (w : float) (h : float) =
  Math.Rect.create (wt.position.x -. w *. 0.5) (wt.position.y -. h *. 0.5) w h

(* Components.Collider is constrained to Component.S ([type t], [component],
   [name] only) — the shape TYPE and its Circle/Box/Capsule constructors are
   not part of that signature at all, and Collider itself (the module that
   actually declares them) is never re-exported by eon_engine.mli under any
   public path. There is no way to name the type Components.Collider.shape
   or write Components.Collider.Circle from application code. The
   constructors still resolve completely unqualified, via type-directed
   disambiguation from the argument's inferred type (pinned by the
   .Components.Collider.shape field projections below) — this is the same
   mechanism that makes bare Parallel/Exclusive work for System.update_kind
   in the previous chapter, just relied on implicitly instead of written out
   by hand, since there is no accessible qualified path to write. *)
let intersects_shapes
    (pa : Components.World_transform.t) (ca : Components.Collider.t)
    (pb : Components.World_transform.t) (cb : Components.Collider.t) =
  match ca.shape, cb.shape with
  | Circle ra,    Circle rb    -> Math.Circle.intersects (circle_of pa ra) (circle_of pb rb)
  | Box (wa, ha), Box (wb, hb) -> Math.Rect.intersects (rect_of pa wa ha) (rect_of pb wb hb)
  | Circle r,     Box (w, h)   -> Math.Circle.intersects_rect (circle_of pa r) (rect_of pb w h)
  | Box (w, h),   Circle r     -> Math.Circle.intersects_rect (circle_of pb r) (rect_of pa w h)
  | _ -> false   (* Capsule: delegate to a physics library *)

(* Collision detection system: query every entity with both
   World_transform and Collider, test all pairs, emit a (entity_a,
   entity_b) event for each hit. Query.Default is the pre-instantiated
   instance -- no need to re-apply Query.Make(Sparse_set_backend.Default)
   by hand, as the original doc did. View.get needs a first-class module
   (module Components.World_transform), not a bare .component value. *)
let detect_collisions (world : World.ro World.t) events =
  let entities = ref [] in
  Query.Default.from world
  |> Query.Default.having_all [ Components.World_transform.name; Components.Collider.name ]
  |> Query.Default.iter (fun view ->
       let entity   = View.entity view in
       let pos      = View.get view (module Components.World_transform) in
       let collider = View.get view (module Components.Collider) in
       entities := (entity, pos, collider) :: !entities);
  let arr = Array.of_list !entities in
  let n   = Array.length arr in
  for i = 0 to n - 2 do
    let (ea, pa, ca) = arr.(i) in
    for j = i + 1 to n - 1 do
      let (eb, pb, cb) = arr.(j) in
      let layers_interact =
        ca.mask land cb.layer <> 0 ||
        cb.mask land ca.layer <> 0
      in
      if layers_interact && intersects_shapes pa ca pb cb
      then
        Double_bus.emit events (ea, eb)
    done
  done

let collision_system_example () =
  let world = World.create () in
  Components.Engine_components.register_all world;
  let events : (Eon_ecs.Entity_id.t * Eon_ecs.Entity_id.t) Events.t = Double_bus.create () in
  let hits = ref [] in
  Double_bus.on events (fun pair -> hits := pair :: !hits);

  let a = World.create_entity world in
  World.add_component world a Components.World_transform.component
    ({ position = Vec2.create 0.0 0.0; rotation = 0.0; scale = Vec2.one } : Components.World_transform.t);
  World.add_component world a Components.Collider.component
    ({ shape = Circle 10.0; layer = 1; mask = 1; is_trigger = false; is_static = false }
     : Components.Collider.t);

  let b = World.create_entity world in
  World.add_component world b Components.World_transform.component
    ({ position = Vec2.create 5.0 0.0; rotation = 0.0; scale = Vec2.one } : Components.World_transform.t);
  World.add_component world b Components.Collider.component
    ({ shape = Circle 10.0; layer = 1; mask = 1; is_trigger = false; is_static = false }
     : Components.Collider.t);

  detect_collisions (World.readonly world) events;
  Double_bus.drain events;
  Double_bus.drain events;
  assert (List.length !hits = 1)

let () =
  vec2_example ();
  rotation_example ();
  reflect_project_clamp_example ();
  vec2i_example ();
  rect_example ();
  circle_example ();
  collision_manifold_example ();
  transform2d_example ();
  interpolation_example ();
  collision_system_example ()
