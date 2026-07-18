type t = { errors : string list }

let empty      = { errors = [] }
let has_errors t = t.errors <> []
