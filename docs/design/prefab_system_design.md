# Prefab System — Thought Dump

## Status

**IMPLEMENTED** — implemented in ecs-036 (`eon_edn` + `eon_engine/prefab/`).

---

## The One-Liner

```ocaml
Prefab_edn.load world "player"  (* -> Entity_id.t with all components attached *)
```

Load a named entity definition from some data source, get back a live entity
in the world with all its components registered and populated. Completely
optional engine feature. `Prefab_edn` here is `eon_engine`'s pre-built
EDN instantiation of the `Prefab.Make` functor — see "Two Seams Needed"
below for why it's a functor rather than a fixed module.

---

## Two Seams Needed

`raw_data` is not one shared runtime representation — it's an **associated
type**, resolved at compile time via a functor, the same pattern already
used throughout this codebase (`System.Make`, `Pipeline.Make`,
`Sparse_set_backend.Make(W : World.S)`). This is what lets `Source`/
`Component_deserializer` be genuinely format-agnostic without any
`Obj.magic` or existential wrapping:

```ocaml
module type Source = sig
  type raw_data
  val load : string -> raw_data
end

module type Component_deserializer = sig
  type raw_data
  val deserialize : World.rw World.t -> Entity_id.t -> key:string -> raw_data -> unit
end

module type Document_shape = sig
  type raw_data
  val extends_of : raw_data -> string option
  val components_of : raw_data -> (string * raw_data) list
  val children_of : raw_data -> raw_data list
  val merge : raw_data -> raw_data -> raw_data  (* base -> override -> merged *)
end

module Make (Source : Source) (Doc : Document_shape with type raw_data = Source.raw_data) : sig
  val register_component :
    string -> (module Component_deserializer with type raw_data = Source.raw_data) -> unit
  val load : World.rw World.t -> string -> Entity_id.t
end
```

`Source` alone isn't enough to implement `load` generically: `resolve`'s
`:extends`-chain walk and `spawn`'s `:components`/`:children` traversal
(see "Nested entities" below) pattern-match on `VMap`/`VKeyword` — that's
an EDN-specific document *shape*, not something a functor generic over an
abstract `Source.raw_data` can express on its own. `Document_shape` is
the decomposition contract that makes the generic algorithm possible:
`Edn_document` implements it via `VMap`/`VKeyword` pattern matching (the
exact `merge_value`/`resolve`/`spawn_one` logic below, extracted into
named functions instead of inlined); a hypothetical non-EDN `Source` that
doesn't want real inheritance can supply a trivial
`merge base override = override`.

An earlier draft of this doc also functorized a `Deserializer` argument
alongside `Source`, mirroring the "two seams" framing symmetrically — but
nothing in `spawn_one`/`load` ever actually used it; the per-key registry
does all the dispatching. That one was genuinely dead weight and was
dropped. `Document_shape` is not the same situation — it's a real,
load-bearing dependency of `load`'s implementation, not a currently-unused
mirror argument.

The dispatch label is `key`, not `component_name`. Deliberately: the
handler registered under a given key isn't required to correspond to
exactly one ECS component. A `"loot_table"` key's handler might set a
single `LootTable` component; a key covering some composite bit of prefab
data might set two or three components, or read/write into a `Service.S`
instead of calling `World.add_component` at all. What's fixed is that the
handler is always entity-scoped — it always has `Entity_id.t` in hand.
That's also exactly where this stops applying: mod data with no owning
entity at all (a global damage-formula table shared across every goblin,
say) doesn't belong here — see "Mod Data With No Owning Entity" below.

Reuses the `Asset_lookup.S` pattern for `Source`. Each `Prefab.Make(...)`
instantiation is monomorphic in its own `raw_data` — an EDN loader has
`raw_data = Eon_edn.value` (see below); a hypothetical protobuf loader has
`raw_data = Protobuf_msg.t`; a precompiled/non-moddable loader has
`raw_data = bytes` decoded straight via `Marshal` or similar, skipping any
text-parsing step entirely. `with type raw_data = Source.raw_data` makes
the compiler enforce that a `Source` and every registered
`Component_deserializer` actually match — no coercion, no shared
universal tree type forced on formats that don't need one.

**Why no `Obj.magic` is needed anywhere here**, unlike `Component.ml`'s
existential wrapper (`Component : 'a component -> any_component`):
`Component.ml` needs that boundary because `World.get_component` must hand
back a genuinely polymorphic `'a option` to an arbitrary caller —
heterogeneous storage in, typed value out, at a call site the registry
doesn't control. `Component_deserializer.deserialize` returns **`unit`** — the
component's real type (`Position.t`, say) is fully consumed *inside* the
closure (parse `raw_data` → `Position.t` → call `World.add_component`,
which is already typed) and never needs to escape. So the per-component
registry inside any one `Prefab.Make(...)` instantiation is just an
ordinary monomorphic `(string, raw_data -> ...) Hashtbl.t`:

```ocaml
Prefab_edn.register_component "position" (module Position_deserializer);
Prefab_edn.register_component "health"   (module Health_deserializer);
```

---

## EDN Out of the Box

Requirement: prefabs must be loadable from EDN files without the user
writing any parsing code. Two consequences:

- **`eon_edn` is a new, standalone project** (own dune package, own repo
  location alongside `eon_ecs`/`eon_engine`, *not* a subdirectory of
  either). It knows nothing about `eon_ecs`, `eon_engine`, components, or
  prefabs — just EDN syntax in, a generic `value` AST out. `eon_engine`
  depends on `eon_edn`, never the reverse. Same layering discipline as
  `eon_ecs` → `eon_engine` (see `project_eon_ecs_boundary` memory).
- Based on `eon_edn_parser.md` (algebraic-effects design, in `docs/design/`
  as the canonical spec for this project) rather than an earlier
  Angstrom-combinator sketch (since removed from the repo). Status:
  **ACCEPTED** — every module (`edn_effects`, `edn_parser`,
  `edn_middleware`) has been compiled and run against OCaml 5.5.0, design
  settled, ready to build.
- `eon_engine` ships a pre-built instantiation — `Prefab.Edn.Make (Root)
  = Prefab.Make (Edn_source.Make (Root)) (Edn_document)`, where
  `Root : sig val path : string end` (same shape as `Asset_lookup.Dir`'s
  parameter — a game points it at its own prefabs directory) and
  `Edn_source.raw_data = Eon_edn.value`. `Edn_source.load name` reads
  `<path>/<name>.edn` and parses it via `eon_edn`; `Edn_document`
  implements `Document_shape` by walking the parsed `value` (map keyword
  → component name, dispatch to the registered per-component
  deserializer). This is the "out of the box" path; it is *an*
  instantiation of `Prefab.Make`, not the only one. A game wanting
  protobuf, a precompiled binary format, or anything else instantiates
  `Prefab.Make` with its own `Source`/`Document_shape` pair and registers
  its own `Component_deserializer`s, and gets the same
  `load`/`register_component` API, entirely independent of `eon_edn`.
  (`Prefab.Edn` is a functor of a root directory, not a single fixed
  module — a fixed module couldn't point at two different games' prefab
  directories.)
- The `eon_engine` side lives in `eon_engine/prefab/`, matching the
  existing per-subsystem layout of `eon_engine/input/`,
  `eon_engine/audio/`, and `eon_engine/render/` — not scattered at the
  top level or folded into `components/`.

### Default deserializers for engine-shipped components

Not every component in `eon_engine/components/` is prefab-authorable.
`Parent`/`Children`/`World_transform` are managed by
`Transform_hierarchy`/`Transform_system` — set via `attach`/`propagate`,
not authored data. A prefab's `:children` vector already drives that
wiring through `spawn`; a `Component_deserializer` for `Parent`/`Children`
would let a prefab author set contradictory state by hand. Excluded on
purpose.

The genuinely authorable set — plain data, no derived/computed fields —
is `Velocity`, `Local_transform`, `Collider`, `Sprite`, `Animation`,
`Camera`, `Tag`.

These ship as an **opt-in helper**, not auto-registered on `Prefab.Edn`
creation:

```ocaml
val register_all :
  (string -> (module Component_deserializer with type raw_data = Eon_edn.value) -> unit) -> unit
```

`Prefab_edn_defaults.register_all` takes a `register_component` function
directly (since `Prefab.Edn` is a functor of a root directory — see
above — there's no single fixed `Prefab.Edn` module to hardcode against).
A game calls it once at startup, passing its own instantiation's
`register_component`:
`Prefab_edn_defaults.register_all My_prefab_edn.register_component`.
Nothing registered by default. Matches the "no central managers,
composable primitives" pattern already used elsewhere (`World`, `Asset`,
`Namespace`) — a game that wants different `Velocity` EDN semantics isn't
fighting an auto-registered default, it just doesn't call `register_all`
(or calls it and re-registers the one key it wants to override —
`register_component` is a plain `Hashtbl.replace`, last registration for
a key wins).

This lives specifically alongside `Prefab.Edn`, not inside the generic
`Prefab.Make` functor — `Prefab.Make` only knows about `Source` and
`Document_shape`, general contracts with no idea `eon_edn` or any
specific component exists. "Ship default deserializers for engine
components" is inherently an EDN-shaped, `eon_engine`-component-shaped
concern, not something the generic functor could express even if it
wanted to.

---

## Why This Is Useful (for my game specifically)

Annual content updates without recompiling. New enemy type = new EDN file,
new component values. No OCaml touched. Dream.

---

## Resolved Design Decisions

### Inheritance/composition

Yes, wanted. `"goblin_archer"` extends `"goblin_base"` by naming it in an
`:extends` key; resolution walks the chain to the root, then deep-merges
maps (a component present on both sides merges field-by-field; the
override's scalar values always win). Only `VMap`s merge recursively —
everything else (a `VVector` of children, a plain scalar) is a flat
replace, no attempt to merge lists element-wise:

`Prefab.Make`'s generic `resolve` is written purely in terms of `Doc`,
not `Eon_edn.value` directly:

```ocaml
(* generic, inside Prefab.Make (Source) (Doc) *)
let resolve (load : string -> Doc.raw_data) name : Doc.raw_data =
  let rec go seen name =
    if List.mem name seen then failwith ("prefab inheritance cycle: " ^ name)
    else
      let doc = load name in
      match Doc.extends_of doc with
      | Some parent -> Doc.merge (go (name :: seen) parent) doc
      | None -> doc
  in
  go [] name
```

`Edn_document`'s `extends_of`/`merge` are exactly the old
`merge_value`/`:extends`-lookup logic, just named and slotted into the
`Document_shape` interface instead of inlined:

```ocaml
(* eon_edn's value is generic — this lives in eon_engine/prefab/, not eon_edn *)
let rec merge (base : Eon_edn.value) (override : Eon_edn.value) : Eon_edn.value =
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

let extends_of = function
  | VMap kvs ->
      (match List.assoc_opt (VKeyword "extends") kvs with
       | Some (VString parent) -> Some parent
       | _ -> None)
  | _ -> None
```

`seen` guards against a cyclic `:extends` chain (`A extends B extends A`
— a typo or bad mod data, not something worth trusting never to happen)
raising instead of recursing forever. Verified: a 3-level chain
(`goblin_archer` → `goblin_base` → `humanoid_base`) still resolves
correctly with the guard in place, and a 2-cycle (`a` → `b` → `a`) raises
`Failure "prefab inheritance cycle: a"` instead of hanging.

Example: `goblin_base` has `{:components {:Health {:hp 50} :Sprite {:id
:goblin}}}`. `goblin_archer` has `{:extends "goblin_base" :components
{:Health {:hp 80} :Ranged_weapon {:damage 12}}}`. Resolving `goblin_archer`
produces `Health.hp = 80` (overridden), `Sprite` intact (inherited
untouched), and `Ranged_weapon` present (added) — verified by actually
running `merge`/`extends_of` against that exact input. `:extends` itself
stays in the merged map, harmlessly — the loader never looks for a
`:extends`-named component deserializer.

Multi-level chains (`archer` extends `goblin` extends `humanoid_base`)
fall out for free — `resolve` recurses to the root before merging back
down, so N-deep inheritance costs nothing extra to support.

### Nested entities

A prefab document can declare a `:children` vector; `Prefab.Make`'s `load`
spawns the parent first, then recursively spawns and `attach`es each
child via `Transform_hierarchy.attach` — the same primitive world-setup
code already uses, not new hierarchy machinery:

A naive version of `spawn` recurses once per hierarchy *depth* level (not
once per component, not once per sibling — branching factor at a single
node is fine either way, since `List.iter`/`List.fold_right` over a node's
own children list only recurses as deep as that node's *own* child count,
not the tree's depth). Depth is the dimension that isn't bounded by
anything — a deeply nested rig or a pathological/generated prefab could in
principle recurse arbitrarily deep, and OCaml doesn't TCO a call sitting
inside a `List.iter` closure. `eon_engine` already made this call once,
for the structurally identical problem: `Transform_system.propagate` was
rewritten from a recursive walk to a tail-recursive explicit work-list
(commit `2a513f4`). `spawn` uses the same shape:

```ocaml
(* generic, inside Prefab.Make (Source) (Doc) *)
let spawn_one world doc parent : World.entity_id * Doc.raw_data list =
  let entity = World.create_entity world in
  (match parent with
   | Some p -> Transform_hierarchy.attach world ~parent:p ~child:entity
   | None -> ());
  List.iter
    (fun (key, data) ->
      match Hashtbl.find_opt registry key with
      | Some (module D : Component_deserializer with type raw_data = Doc.raw_data) ->
          (* set_component, not add_component — see below *)
          D.deserialize world entity ~key data
      | None -> failwith ("no deserializer registered for key " ^ key))
    (Doc.components_of doc);
  entity, Doc.children_of doc

let load world name : World.entity_id =
  let root_doc = resolve Source.load name in
  let root_entity, root_children = spawn_one world root_doc None in
  let rec loop = function
    | [] -> ()
    | (doc, parent) :: rest ->
        let entity, children = spawn_one world doc (Some parent) in
        let next = List.fold_right (fun child acc -> (child, entity) :: acc) children rest in
        loop next
  in
  loop (List.fold_right (fun child acc -> (child, root_entity) :: acc) root_children []);
  root_entity
```

`Edn_document.components_of`/`children_of` are exactly the old inline
`VMap`/`VKeyword "components"`/`VKeyword "children"` matching, moved into
named functions:

```ocaml
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
```

`loop` is tail-recursive — stack depth is O(1) regardless of hierarchy
depth; the pending work lives on the heap as an ordinary list, exactly
like `propagate`'s work-list. `fold_right` (not `fold_left`) on each
node's own `children` list is what keeps sibling order matching document
order — verified by running both the naive recursive version and this
work-list version against the same nested-prefab input and diffing the
resulting entity IDs, attach edges, and per-component deserialize calls:
identical on every field. Also stress-tested with a synthetic
1,000,000-level-deep chain (a stand-in for "much deeper than any real
prefab would ever be") — the work-list version handles it without issue;
the naive recursive version would stack-overflow on the same input. This
verification predates the `Document_shape` extraction, but the traversal
shape (`loop`'s work-list) is untouched by it — only "how do I get a
node's children" changed from an inline match to `Doc.children_of`.

`despawn_recursive` (already in `Transform_hierarchy`) is the natural
counterpart when a spawned prefab entity is torn down later — no new
teardown path needed either.

**Design note this surfaced:** component deserializers should call
`World.set_component`, not `World.add_component` — per the component
lifecycle rules, `set_component` "promotes to add if missing," so it
handles both the fresh-spawn case (`spawn` above) and, later, a hot-reload
case (re-running a deserializer against an *existing* entity) with the
exact same deserializer code. Using `add_component` in `deserialize`
would raise on the second call and force two different code paths.

### Hot reload

Still optional, not designed up front — but the
`set_component`-not-`add_component` choice above is specifically so that
if/when this gets built, `Prefab.reload world entity name` can just
re-`resolve` the doc and re-run the same per-component `deserialize`
calls against the same `entity`, no separate "update" variant of
`Component_deserializer` needed. The open part is `:children` diffing
(new children need `attach`, removed ones need `despawn_recursive`,
existing ones need to reload in place) — deliberately not designed now
since hot reload itself is still optional.

### Deserializer registry location

**Not `Service.S`** — plain per-instantiation `Hashtbl` state, module-level
inside `Prefab.Make`'s functor body:

```ocaml
let registry : (string, (module Component_deserializer with type raw_data = Source.raw_data)) Hashtbl.t =
  Hashtbl.create 32

let register_component name deser = Hashtbl.replace registry name deser
```

Originally designed as a `Service.S` (per-world, composing with
`Namespace.S` for cross-world sharing). Reversed after finding a real bug:
`Service.key` for a bare polymorphic variant (`` `Prefab_registry ``) is
an *immediate* value — the same integer regardless of which functor
application computes it, since it's written once, literally, inside
`Prefab.Make`'s shared functor body. Two separate `Prefab.Make(...)`
instantiations registering on the *same* `World` (e.g. an EDN-based
loader and a precompiled-binary-based loader coexisting in one running
game) would silently collide on the identical `Service` slot —
`World.add_service` is a plain `Hashtbl.replace`, so whichever
instantiation calls its init last silently wipes out the other's entire
registry. Confirmed by reading `Resource_store.ml`: `services` is an
ordinary `Hashtbl.t` using structural equality, not physical identity, so
there's no accidental protection here.

This isn't a "give the functor a unique key" fix, either — the key is
generated *inside* `Prefab.Make`'s own body, never written by the calling
game, so there's no call-site mistake to make (unlike the general
`Service.Make` convention, where picking a distinct top-level variant
genuinely is the caller's job — see "Resource store key collisions" in
`CLAUDE.md`). And on reflection, `Service.S`/`World`-scoping was never
the right model for this data in the first place: a deserializer
registration (`"position" -> Position_deserializer`) is static, load-time
configuration for one `Prefab.Make` instantiation — there's no scenario
where World A and World B, using the *same* instantiation, would want
different deserializers for the same key. Plain module-level state is
genuinely isolated per functor application automatically (OCaml's module
system does this for free, no key involved at all), and it's the exact
pattern already used successfully in Phase 1 — `Edn_middleware.tag_registry`
is the same shape.

---

## Mod Data With No Owning Entity

Not everything a mod wants to add is a component on some entity. A
damage-formula shared by every goblin, a global loot-rarity weight table —
these aren't per-entity data, so they don't fit `Component_deserializer`
no matter how the `key` label is generalized (`Entity_id.t` is a required
argument; there's nothing to pass one of).

This isn't a gap — it's a different, already-designed extension point:
`eon_edn`'s tag/middleware system (`register_tag_handler`, `eon_edn_parser.md`).
Crucially, this resolves **inline, in the same parse**, not as a separate
loading step. When `goblin`'s prefab document references a formula from
inside one of its own components:

```clojure
{:components
 {:Damage_profile {:formula #eon/formula {:linear {:base 10 :per_level 2.5}}}}}
```

the `#eon/formula` tag is handled *at the point it's encountered*, during
the single `Edn_parser.value ()` call that reads the whole `goblin`
document — before `Prefab`'s `spawn_one`/`Component_deserializer.deserialize`
ever runs. The registered handler validates the shape right there — it does
**not** interpret an expression (see `game_calculations_example.md`'s
"Representing Formulas" for why — that discussion is `eon_game`-layer
content, not engine design, so it lives there rather than here):

```ocaml
register_tag_handler "eon/formula" (fun _ v ->
  match v with
  | VMap [ (VKeyword ("linear" | "percent_of" | "diminishing_returns" | "tiered"), VMap _) ] ->
      VTagged ("eon/formula", v)
  | _ -> failwith "eon/formula: unrecognized shape")
```

By the time `Damage_profile`'s `Component_deserializer.deserialize` receives its
`raw_data` for the `:formula` key, it's already looking at the
pre-validated `VTagged ("eon/formula", ...)` shape — its only remaining
job is the final typed conversion into the native `formula` variant
`Damage_profile.t` needs. No second load, no separate registry lookup, no
reference-by-name indirection — the formula is just data embedded in the
document, resolved once, in place.

Where a *shared* registry genuinely is needed is when the same formula is
meant to be reused verbatim across many entities rather than redefined
per-document — in that case the tag handler's job changes slightly: parse
once, stash the result keyed by some id in a `Service.S`/`Hashtbl`, and
return a lightweight reference (`VTagged ("eon/formula-ref", VString
id)`) that each referencing component's deserializer resolves against
that registry. Same tag mechanism either way; the difference is only
whether the handler embeds the result directly or stores-and-references
it. `Prefab` itself never needs to know which — it only ever sees the
fully-resolved `raw_data` for whichever key it's deserializing.

---

Representing formulas themselves (as data, not lambdas or interpreted
expressions) and a full worked example against `game_calculations.md`'s
actual combat math are `eon_game`-layer content, not engine design — see
`docs/eon_game/game_calculations_example.md`.

---

## Mod System — Not the Engine's Problem

A full mod system is not an `eon_engine` concern. The prefab system's
`Source` seam is sufficient — the engine just loads named entities from
whatever source you give it. Mod support is built on top by the game:

- `eon_engine` — `Prefab_edn.load world "goblin"` (or whichever
  `Prefab.Make` instantiation the game picked) via `Source`
- `eon_game` — plug in a `Source` that reads from base game folder OR
  a Steam Workshop folder, with whatever priority and conflict rules the
  game wants

The engine is oblivious to what a mod is. Validation, versioning, load
order, conflict resolution — all game responsibility. If mods never happen,
the prefab system still pays for itself in development ergonomics alone.
