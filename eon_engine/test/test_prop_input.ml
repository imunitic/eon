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

let prop_touch_id_roundtrip =
  QCheck.Test.make ~name:"Touch_id.of_int/to_int round-trips" ~count:200
    QCheck.int (fun i -> Touch_id.to_int (Touch_id.of_int i) = i)

let tests =
  List.map QCheck_alcotest.to_alcotest
    [ prop_scripted_replays_touch_frames; prop_touch_id_roundtrip ]
