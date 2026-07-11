open Eon_edn.Edn_effects

type raw_data = value

let extends_of = function
  | VMap kvs ->
      (match List.assoc_opt (VKeyword "extends") kvs with
       | Some (VString parent) -> Some parent
       | _ -> None)
  | _ -> None

let components_of = function
  | VMap kvs ->
      (match List.assoc_opt (VKeyword "components") kvs with
       | Some (VMap comps) ->
           List.filter_map
             (function VKeyword key, data -> Some (key, data) | _ -> None)
             comps
       | _ -> [])
  | _ -> []

let children_of = function
  | VMap kvs ->
      (match List.assoc_opt (VKeyword "children") kvs with
       | Some (VVector cs) -> cs
       | _ -> [])
  | _ -> []

let rec merge base override =
  match base, override with
  | VMap base_kvs, VMap override_kvs ->
      let merged =
        List.fold_left
          (fun acc (k, v) ->
            match List.assoc_opt k acc with
            | Some existing -> (k, merge existing v) :: List.remove_assoc k acc
            | None -> (k, v) :: acc)
          base_kvs override_kvs
      in
      VMap merged
  | _, override -> override
