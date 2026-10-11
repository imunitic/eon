module type ENCODE = sig
  type format

  val encode : Edn_effects.value -> Edn_bytes.t
end

module type DECODE = sig
  type format

  val decode : Edn_bytes.t -> Edn_effects.value
end
