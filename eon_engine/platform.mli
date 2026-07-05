(** Platform seam — bundles input and audio backends for [Loop.Make].

    Supply a [Platform.S] when instantiating [Loop.Make]. For servers, tests,
    and scripted simulation use [Platform.Headless]. Game binaries supply a
    concrete platform backed by their chosen windowing and audio library. *)

module type S = sig
  type t
  module Input_backend     : Input_backend.S
  module Audio_backend     : Audio_backend.S
  module Rendering_backend : Rendering_backend.S
end

(** Headless platform — null input, audio, and rendering backends.
    Suitable for servers, CI, and scripted integration tests. *)
module Headless : S with type t = [ `Headless ]
