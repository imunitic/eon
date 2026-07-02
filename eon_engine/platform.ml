module type S = sig
  type t
  module Input_backend : Input_backend.S
  module Audio_backend : Audio_backend.S
end

module Headless = struct
  type t = [ `Headless ]
  module Input_backend = Input_backend.Null
  module Audio_backend = Audio_backend.Null
end
