type t = int

let of_int i = i
let to_int i = i
let compare = Int.compare

module Set = Set.Make (struct
  type nonrec t = t

  let compare = compare
end)

module Map = Map.Make (struct
  type nonrec t = t

  let compare = compare
end)
