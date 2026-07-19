(* Transcribed into doc/reading.mld — keep in sync by hand. *)

let quick_start () =
  let v =
    Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value
      {|{:name "Crab" :position [1 2] :alive true}|}
  in
  match v with
  | Eon_edn.Edn_effects.VMap _ -> print_endline "parsed a map"
  | _ -> assert false

let parse_a_list () =
  match Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value {|(1 2 3)|} with
  | Eon_edn.Edn_effects.VList [ VNumber 1.; VNumber 2.; VNumber 3. ] -> ()
  | _ -> assert false

(* [run] deliberately does not handle Tag/Meta — parsing a tagged value
   via [run] alone raises an unhandled-effect error. *)
let tag_without_middleware_raises () =
  match Eon_edn.Edn_parser.run Eon_edn.Edn_parser.value {|#uuid "abc"|} with
  | _ -> assert false
  | exception _ -> ()

let () =
  quick_start ();
  parse_a_list ();
  tag_without_middleware_raises ()
