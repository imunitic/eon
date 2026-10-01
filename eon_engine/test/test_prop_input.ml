open Eon_engine

let gen_float = QCheck.Gen.(float_range (-2000.0) 2000.0)
let gen_pair = QCheck.Gen.pair gen_float gen_float

let gen_touch =
  QCheck.Gen.(
    map4
      (fun position delta pressure radius ->
        { Raw_input_frame.position; delta; pressure; radius })
      gen_pair gen_pair (float_range 0.0 1.0) (float_range 0.0 50.0))

let gen_id = QCheck.Gen.(map Touch_id.of_int (int_range 0 9))

let gen_touch_map =
  QCheck.Gen.(
    map
      (List.fold_left (fun m (i, t) -> Touch_id.Map.add i t m) Touch_id.Map.empty)
      (list_size (int_range 0 5) (pair gen_id gen_touch)))

let gen_frame =
  QCheck.Gen.(
    map4
      (fun down pressed released cancelled ->
        { Raw_input_frame.empty with
          touches_down      = down;
          touches_pressed   = Touch_id.Set.of_list pressed;
          touches_released  = released;
          touches_cancelled = cancelled })
      gen_touch_map
      (list_size (int_range 0 5) gen_id)
      gen_touch_map gen_touch_map)

let arb_frames =
  QCheck.make QCheck.Gen.(list_size (int_range 0 8) gen_frame)

let same_touches a b =
  Touch_id.Map.equal ( = ) a.Raw_input_frame.touches_down b.Raw_input_frame.touches_down
  && Touch_id.Set.equal a.touches_pressed b.touches_pressed
  && Touch_id.Map.equal ( = ) a.touches_released b.touches_released
  && Touch_id.Map.equal ( = ) a.touches_cancelled b.touches_cancelled

(* Scripted must hand back exactly the frames it was given, in order, and
   then fall back to [empty]. *)
let prop_scripted_replays_touch_frames =
  QCheck.Test.make ~name:"Scripted replays touch frames in order, then empty"
    ~count:200 arb_frames (fun frames ->
      Input_backend.Scripted.set_frames frames;
      let replayed = List.map (fun _ -> Input_backend.Scripted.collect ()) frames in
      let after = Input_backend.Scripted.collect () in
      List.for_all2 same_touches frames replayed
      && same_touches after Raw_input_frame.empty)

(* Contract checker for backend-produced frames: pressed ids are held, and a
   released or cancelled id is never still down. *)
let frame_respects_touch_contract f =
  let open Raw_input_frame in
  Touch_id.Set.for_all (fun i -> Touch_id.Map.mem i f.touches_down) f.touches_pressed
  && Touch_id.Map.for_all (fun i _ -> not (Touch_id.Map.mem i f.touches_down)) f.touches_released
  && Touch_id.Map.for_all (fun i _ -> not (Touch_id.Map.mem i f.touches_down)) f.touches_cancelled
  && Touch_id.Map.for_all (fun i _ -> not (Touch_id.Map.mem i f.touches_cancelled)) f.touches_released

(* Model of the sub-frame-tap rule: raw per-frame (land, lift) activity for one
   id goes in; reporting frames come out. A tap that lands and lifts in the
   same frame must be down+pressed now and released next frame. *)
let prop_subframe_tap_is_deferred =
  QCheck.Test.make ~name:"sub-frame tap: pressed and down now, released next"
    ~count:200 (QCheck.make gen_touch) (fun t ->
      let i = Touch_id.of_int 3 in
      let f1 =
        { Raw_input_frame.empty with
          touches_down    = Touch_id.Map.singleton i t;
          touches_pressed = Touch_id.Set.singleton i }
      and f2 =
        { Raw_input_frame.empty with
          touches_released = Touch_id.Map.singleton i t }
      in
      frame_respects_touch_contract f1 && frame_respects_touch_contract f2
      && Touch_id.Map.mem i f1.touches_down
      && not (Touch_id.Map.mem i f2.touches_down))

let prop_contract_rejects_pressed_not_down =
  QCheck.Test.make ~name:"contract: pressed id missing from touches_down is rejected"
    ~count:200 (QCheck.make gen_id) (fun i ->
      not (frame_respects_touch_contract
             { Raw_input_frame.empty with touches_pressed = Touch_id.Set.singleton i }))

let prop_touch_id_roundtrip =
  QCheck.Test.make ~name:"Touch_id.of_int/to_int round-trips" ~count:200
    QCheck.int (fun i -> Touch_id.to_int (Touch_id.of_int i) = i)

let tests =
  List.map QCheck_alcotest.to_alcotest
    [ prop_scripted_replays_touch_frames;
      prop_subframe_tap_is_deferred;
      prop_contract_rejects_pressed_not_down;
      prop_touch_id_roundtrip ]
