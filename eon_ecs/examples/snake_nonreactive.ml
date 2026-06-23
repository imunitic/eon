open Eon_ecs
open Notty
open Notty.Infix

module Term = Notty_unix.Term
module System = Eon_ecs.System.Default
module Pipeline = Eon_ecs.Pipeline.Default
module Progress = Eon_ecs.Progress.Default

(*
  Architecture summary:
  - Simulation is data-centric ECS: systems query components and mutate world state.
  - Input is polled in the renderer and written back as component/data updates.
  - Rendering is isolated in Snake_renderer and runs after ECS tick/drain.
  - Loop orchestration controls timing and frame order.
  - The terminal and all game state live in the World; no module-level mutable state.
*)

type pos = { x : int; y : int }
type direction = int * int

(* Grid & timing *)
let grid_width = 40
let grid_height = 20
let fixed_step_s = 0.125
let cell_width = 2

(* Components *)
let trail_component = "Trail"
let direction_component = "Direction"
let alive_component = "Alive"
let position_component = "Position"

(* World data keys *)
let failf fmt = Printf.ksprintf failwith fmt
let paused_key = `Paused
let quit_key = `Quit
let rng_key = `Snake_rng
let score_key = `Snake_score
let any_alive_key = `Snake_any_alive
let term_key = `Snake_term

(* Pure helpers *)
let pos_equal a b = a.x = b.x && a.y = b.y

let in_bounds p = p.x >= 0 && p.x < grid_width && p.y >= 0 && p.y < grid_height

let is_opposite (dx1, dy1) (dx2, dy2) = dx1 + dx2 = 0 && dy1 + dy2 = 0

let rec all_but_last = function
  | [] -> []
  | [ _ ] -> []
  | x :: xs -> x :: all_but_last xs

let occupied snake p = List.exists (fun seg -> pos_equal seg p) snake

let spawn_food rng snake =
  let capacity = grid_width * grid_height in
  if List.length snake >= capacity then None
  else
    let rec pick () =
      let candidate =
        { x = Random.State.int rng grid_width; y = Random.State.int rng grid_height }
      in
      if occupied snake candidate then pick () else Some candidate
    in
    pick ()

let is_paused world =
  match World.get_data world paused_key with
  | Some paused -> paused
  | None -> false

let score world =
  match World.get_data world score_key with
  | Some v -> v
  | None -> 0

(* World setup *)
let init_game_state world ~snake_entity ~food_entity =
  let rng = Random.State.make_self_init () in
  World.set_data world rng_key rng;
  let cx = grid_width / 2 in
  let cy = grid_height / 2 in
  let segments =
    [ { x = cx; y = cy }; { x = cx - 1; y = cy }; { x = cx - 2; y = cy } ]
  in
  World.set_component world snake_entity ~name:trail_component segments;
  World.set_component world snake_entity ~name:direction_component (1, 0);
  World.set_component world snake_entity ~name:alive_component true;
  World.set_data world score_key 0;
  World.set_data world any_alive_key true;
  World.set_data world paused_key false;
  World.set_data world quit_key false;
  match spawn_food rng segments with
  | Some food -> World.set_component world food_entity ~name:position_component food
  | None -> World.set_component world snake_entity ~name:alive_component false

let build_world () =
  let world = World.create () in
  ignore (World.register_component world ~name:trail_component ~id:0 : pos list Component.component);
  ignore (World.register_component world ~name:direction_component ~id:1 : direction Component.component);
  ignore (World.register_component world ~name:alive_component ~id:2 : bool Component.component);
  ignore (World.register_component world ~name:position_component ~id:3 : pos Component.component);

  let snake = World.create_entity world in
  World.add_component world snake ~name:trail_component [];
  World.add_component world snake ~name:direction_component (1, 0);
  World.add_component world snake ~name:alive_component true;

  let food = World.create_entity world in
  World.add_component world food ~name:position_component { x = 0; y = 0 };

  init_game_state world ~snake_entity:snake ~food_entity:food;
  world

type game = {
  world : World.t;
  progress : [ `Input | `Gameplay ] Progress.t;
}

(* ECS systems & pipeline *)
let build_game () =
  let world = build_world () in

  let ascii_lower_of_key = function
    | `ASCII c -> Some (Char.lowercase_ascii c)
    | `Uchar u ->
        if Uchar.to_int u <= 0x7F then
          Some (Char.lowercase_ascii (Char.chr (Uchar.to_int u)))
        else
          None
    | _ -> None
  in

  let decode_direction = function
    | `Arrow `Up -> Some (0, -1)
    | `Arrow `Down -> Some (0, 1)
    | `Arrow `Left -> Some (-1, 0)
    | `Arrow `Right -> Some (1, 0)
    | key -> begin
        match ascii_lower_of_key key with
        | Some 'w' -> Some (0, -1)
        | Some 's' -> Some (0, 1)
        | Some 'a' -> Some (-1, 0)
        | Some 'd' -> Some (1, 0)
        | _ -> None
      end
  in

  let drain_input term current_direction paused =
    let input_fd, _ = Term.fds term in
    let input_ready () =
      let ready, _, _ = Unix.select [ input_fd ] [] [] 0.0 in
      ready <> []
    in
    (* Drain all currently pending key events without blocking the frame. *)
    let rec loop direction quit_requested paused =
      if Term.pending term || input_ready () then
        match Term.event term with
        | `Key (key, _mods) ->
            if key = `Escape || match ascii_lower_of_key key with Some 'q' -> true | _ -> false then
              loop direction true paused
            else if match ascii_lower_of_key key with Some 'p' -> true | _ -> false then
              loop direction quit_requested (not paused)
            else
              let next_direction =
                match decode_direction key with
                (* Prevent 180-degree turns so the snake cannot reverse into itself instantly. *)
                | Some proposed when not (is_opposite direction proposed) -> proposed
                | _ -> direction
              in
              loop next_direction quit_requested paused
        | `End -> loop direction true paused
        | _ -> loop direction quit_requested paused
      else
        (direction, quit_requested, paused)
    in
    loop current_direction false paused
  in

  let input_system =
    System.make
      ~update:(fun world _dt ->
        match World.get_data world term_key with
        | None -> ()
        | Some term ->
            let paused = is_paused world in
            Query.iter2 world direction_component alive_component (fun entity direction alive ->
                if alive then begin
                  let next_direction, quit_requested, next_paused =
                    drain_input term direction paused
                  in
                  World.set_component world entity ~name:direction_component next_direction;
                  World.set_data world paused_key next_paused;
                  if quit_requested then World.set_data world quit_key true
                end))
      ~kind:`Variable
      ()
  in

  let movement_system =
    System.make
      ~update:(fun world _dt ->
        if is_paused world then ()
        else begin
          (* ECS pattern:
             1) read required world state (food position) by querying component shape,
             2) query entities by component shape (trail + direction + alive),
             3) compute next state,
             4) write component/data updates back to the world. *)
          let food_ref = ref None in
          Query.iter1 world position_component (fun entity food ->
              if !food_ref = None then food_ref := Some (entity, food));
          match !food_ref with
          | None -> ()
          | Some (food_entity, food_pos) ->
              Query.iter3 world trail_component direction_component alive_component
                (fun entity segments direction alive ->
                  if alive then
                    let head =
                      match segments with
                      | h :: _ -> h
                      | [] -> { x = grid_width / 2; y = grid_height / 2 }
                    in
                    (* Authoritative direction guard in simulation:
                       ignore opposite turns even if input timing produced one. *)
                    let effective_direction =
                      match segments with
                      | head :: neck :: _ ->
                          let current = (head.x - neck.x, head.y - neck.y) in
                          if is_opposite direction current then current else direction
                      | _ -> direction
                    in
                    if effective_direction <> direction then
                      World.set_component world entity ~name:direction_component effective_direction;
                    let dx, dy = effective_direction in
                    let new_head = { x = head.x + dx; y = head.y + dy } in
                    let grew = pos_equal food_pos new_head in
                    (* If not growing this tick, tail moves away, so exclude it from self-hit check. *)
                    let body_for_collision = if grew then segments else all_but_last segments in
                    if (not (in_bounds new_head)) || occupied body_for_collision new_head then
                      World.set_component world entity ~name:alive_component false
                    else begin
                      (* Write-back phase: persist updated trail and related world data. *)
                      let new_segments =
                        if grew then new_head :: segments
                        else new_head :: all_but_last segments
                      in
                      World.set_component world entity ~name:trail_component new_segments;
                      if grew then begin
                        let rng =
                          match World.get_data world rng_key with
                          | Some v -> v
                          | None -> failf "missing world data Snake_rng"
                        in
                        begin
                          match spawn_food rng new_segments with
                          | Some new_food ->
                              World.set_component world food_entity ~name:position_component new_food;
                              World.set_data world score_key (score world + 1)
                          | None -> World.set_component world entity ~name:alive_component false
                        end
                      end
                    end)
        end)
      ~kind:`Fixed
      ()
  in

  let alive_system =
    System.make
      ~update:(fun world _dt ->
        let any_alive = ref false in
        Query.iter1 world alive_component (fun _ alive -> if alive then any_alive := true);
        World.set_data world any_alive_key !any_alive)
      ~kind:`Fixed
      ()
  in

  let pipeline =
    Pipeline.create ()
    |> Pipeline.add_phase `Input
    |> Pipeline.add_phase `Gameplay
    |> Pipeline.before ~earlier:`Input ~later:`Gameplay
    |> Pipeline.add_system `Input input_system
    |> Pipeline.add_system `Gameplay movement_system
    |> Pipeline.add_system `Gameplay alive_system
  in

  Pipeline.register_all pipeline world;
  let progress = Progress.create ~mode:(Progress.Hybrid fixed_step_s) pipeline in
  { world; progress }

(* Rendering & input *)
module Snake_renderer = struct
  type world = World.t
  type result = unit

  let first_food world =
    let found = ref None in
    Query.iter1 world position_component (fun entity food ->
        if !found = None then found := Some (entity, food));
    !found

  let render_world term world paused =
    match first_food world with
    | None -> ()
    | Some (_food_entity, food) ->
        let snake_segments = ref [] in
        let snake_alive = ref false in
        Query.iter2 world trail_component alive_component (fun _entity segments alive ->
            if !snake_segments = [] then begin
              snake_segments := segments;
              snake_alive := alive
            end);

        let snake_cells = Hashtbl.create (List.length !snake_segments) in
        List.iter
          (fun p ->
            let idx = (p.y * grid_width) + p.x in
            Hashtbl.replace snake_cells idx ())
          !snake_segments;

        let board =
          I.tabulate (grid_width + 2) (grid_height + 2) (fun x y ->
            let wall = x = 0 || y = 0 || x = grid_width + 1 || y = grid_height + 1 in
            if wall then
              I.char A.(bg lightblack) ' ' cell_width 1
            else
              let gx = x - 1 in
              let gy = y - 1 in
              let idx = (gy * grid_width) + gx in
              let at_food = food.x = gx && food.y = gy in
              let attr =
                if Hashtbl.mem snake_cells idx then A.(bg lightwhite)
                else if at_food then A.(bg lightred)
                else A.(bg black)
              in
              I.char attr ' ' cell_width 1)
        in

        let hud_text =
          if !snake_alive && paused then
            Printf.sprintf "Snake | Score: %d | PAUSED (p) | Move: arrows/WASD | Quit: q/esc" (score world)
          else if !snake_alive then
            Printf.sprintf "Snake | Score: %d | Move: arrows/WASD | Pause: p | Quit: q/esc" (score world)
          else
            Printf.sprintf "Game Over | Score: %d | Restarting... | Quit: q/esc" (score world)
        in
        let hud = I.string A.(fg lightgreen ++ st bold) hud_text in
        let frame = hud <-> I.void 0 1 <-> board in
        let cols, rows = Term.size term in
        Term.image term (I.vsnap ~align:`Top rows (I.hsnap ~align:`Left cols frame))

  let render world ~dt:_dt =
    match World.get_data world term_key with
    | None -> ()
    | Some term ->
        render_world term world (is_paused world)
end

(* Loop wiring *)
module Noop_buses = struct
  let collect () = ()
  let drain   () = ()
end

module Snake_loop = Eon_ecs.Loop.Make
    (Eon_ecs.Clock.Mtime)
    (Eon_ecs.Loop.Progress_adapter)
    (Snake_renderer)
    (Noop_buses)

(* Runtime session orchestration *)
let should_quit world =
  match World.get_data world quit_key with
  | Some quit -> quit
  | None -> false

let any_alive world =
  match World.get_data world any_alive_key with
  | Some alive -> alive
  | None -> true

let rec run_session term =
  let game = build_game () in
  World.set_data game.world term_key term;
  let final_world =
    Snake_loop.run
      ~render_initial:true
      ~progress:game.progress
      ~world:game.world
      ~should_continue:(fun world () -> not (should_quit world) && any_alive world)
      ()
  in
  if not (should_quit final_world) then run_session term

let () =
  let term = Term.create () in
  Fun.protect
    ~finally:(fun () -> Term.release term)
    (fun () -> run_session term)
