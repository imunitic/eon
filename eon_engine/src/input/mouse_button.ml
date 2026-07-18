type t = Left | Right | Middle | Extra_1 | Extra_2

module Set = Set.Make (struct
  type nonrec t = t

  let compare = compare
end)
