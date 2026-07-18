(** Composable resolution of {!Edn_effects.Tag}/{!Edn_effects.Meta}
    effects left unhandled by {!Edn_parser.run}.

    A [handler] wraps a thunk and may fully resolve a {!Edn_effects.Tag}
    effect (terminating it) or forward it ([None]) to whichever handler is
    next — either another middleware handler, or {!default_handler}, which
    must always be the outermost wrapper. *)

type tag_handler = string -> Edn_effects.value -> Edn_effects.value
type meta_handler = Edn_effects.value -> Edn_effects.value -> Edn_effects.value

val register_tag_handler : string -> tag_handler -> unit
(** Register a handler for a specific [#tag]. Looked up by
    {!default_handler}; an unregistered tag resolves to
    [VTagged (name, v)]. *)

val find_tag : string -> tag_handler
(** The handler registered for [name], or the default
    [VTagged]-wrapping fallback if none was registered. *)

val default_meta : meta_handler
(** [default_meta m v = VMeta (m, v)]. *)

type handler = (unit -> Edn_effects.value) -> Edn_effects.value

val compose : handler -> handler -> handler
(** [compose a b] installs [a]'s handler around [b]'s — [b] sits closer to
    the parser and gets first refusal on each effect. *)

val default_handler : handler
(** The outermost, last-resort handler: resolves {!Edn_effects.Tag} via
    the registry ({!register_tag_handler}/{!find_tag}) and
    {!Edn_effects.Meta} via {!default_meta}. Must wrap outside every user
    middleware handler (see {!run_with_middleware}). *)

val log_tags : handler
(** Logs every tag encountered (to stdout) as a side effect, then
    forwards so a later handler still resolves the actual value. *)

val strict_tags : string list -> handler
(** [strict_tags allowed] rejects (raises [Failure]) any tag not in
    [allowed]; allowed tags are forwarded so a later handler still
    resolves the actual value. *)

val identity : handler
(** A frame-less passthrough — installs no effect handler at all. The
    correct fold seed for composing a [handler list] (see
    {!run_with_middleware}); using {!default_handler} as the seed instead
    would make it the innermost handler and shadow all middleware. *)

val run_with_middleware :
  ?handlers:handler list -> (unit -> Edn_effects.value) -> string -> Edn_effects.value
(** [run_with_middleware ?handlers parser input] parses [input] via
    [parser] (typically [Edn_parser.value]), with [handlers] installed
    between the reader and {!default_handler}. Refusal order runs from
    the *last* element of [handlers] (nearest the reader, gets first
    crack at each effect) to the *first* element (nearest
    {!default_handler}, gets last crack among the middleware) — see
    {!compose}. E.g. with [~handlers:[log_tags; strict_tags [...]]],
    [strict_tags] is asked first. *)
