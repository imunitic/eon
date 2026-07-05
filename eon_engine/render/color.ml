type t = { r : float; g : float; b : float; a : float }

let create r g b a = { r; g; b; a }

let white       = { r = 1.0; g = 1.0; b = 1.0; a = 1.0 }
let black       = { r = 0.0; g = 0.0; b = 0.0; a = 1.0 }
let transparent = { r = 0.0; g = 0.0; b = 0.0; a = 0.0 }
