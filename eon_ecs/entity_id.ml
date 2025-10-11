type t = {
    index: int;
    generation: int;
  }

let make index generation = {index; generation }
let index e = e.index
let generation e = e.generation
let equal a b = a.index = b.index && a.generation = b.generation
let invalid = {index = -1; generation = -1}
