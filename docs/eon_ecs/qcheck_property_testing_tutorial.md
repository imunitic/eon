# QCheck Property Testing in Eon ECS

This short tutorial explains two styles of property testing with QCheck:

1. Simple property tests
2. Model-based property tests

The examples use `Sparse_set`, since we already have both unit tests and a real property test for it.

## Why Property Tests?

Unit tests check specific examples.

Property tests check that general invariants hold across many generated inputs.

In practice, they complement each other:

- Unit tests: great for precise behavior and edge-case documentation.
- Property tests: great for exploring lots of combinations automatically.

---

## Style 1: Simple Property Tests

Use this style when you can express behavior as:

`for all input x, predicate P (f x) holds`

### Example: `set_value` then `get`

```ocaml
let prop_set_value_get_contains =
  QCheck.Test.make
    ~name:"set_value then get/contains"
    QCheck.(pair (int_range 0 63) int)
    (fun (idx, v) ->
      let set = Sparse_set.create () in
      let e = Entity_id.make idx 0 in
      Sparse_set.set_value set e v;
      Sparse_set.contains set e
      && Sparse_set.get set e = Some v
      && Sparse_set.size set = 1)
```

### What this gives you

- Very easy to read
- Fast to write
- Great for local postconditions

### Limits

- Harder to cover long, stateful operation sequences
- Can miss bugs caused by interleavings (`add -> remove -> add -> set_value`, etc.)

---

## Style 2: Model-Based Property Tests

Use this style for stateful systems where correctness is best described as:

`system under test behaves like a trusted reference model`

### Existing example in this repository

See: `eon_ecs/test/test_prop_sparse_set.ml`

The property generates random operation sequences:

- `Add (idx, value)`
- `Set_value (idx, value)`
- `Remove idx`

Each operation is applied to:

1. Real `Sparse_set`
2. Reference `Int_map` (`Map.Make(Int)`)

At the end, the property checks invariants such as:

- counts match (`Sparse_set.size` vs `Int_map.cardinal`)
- membership matches
- `iter` output matches model content
- absent/present agreement over a bounded key domain

### Why this is powerful

It tests behavior across many operation histories, not just one-step scenarios.

This is usually the best style for:

- ECS stores (`Sparse_set`, resource stores, registries)
- Buses with collect/drain semantics
- entity lifecycles and generation safety
- pipeline/progress/loop ordering behavior

---

## Choosing Between the Two

Use simple properties when:

- You are validating a pure/local rule
- There is little or no internal state evolution

Use model-based properties when:

- Behavior depends on sequences of operations
- You can define a simpler trusted model
- You want stronger confidence in mutable/stateful code

You can also combine both in the same test file:

- A few simple properties for basic contracts
- One model-based property for sequence-level correctness

---

## Debugging and Reproducing Failures

`qcheck-alcotest` prints a seed at runtime:

```txt
qcheck random seed: 125386556
```

Re-run with that seed to reproduce:

```sh
QCHECK_SEED=125386556 opam exec -- dune exec eon_ecs/test/test_main.exe -- test "Sparse Set \(QCheck\)"
```

Useful environment variables:

- `QCHECK_SEED=<int>`: replay a run deterministically
- `QCHECK_VERBOSE=1`: more detailed output
- `QCHECK_COUNT=<n>`: increase number of generated cases
- `QCHECK_LONG=1`: enable long test mode for tests that use it

---

## Suggested Path for New Property Suites

When adding a new subsystem:

1. Start with one simple property to validate a core contract.
2. Add one model-based property for state transitions.
3. Keep generators bounded and shrink-friendly.
4. Register the suite in `eon_ecs/test/test_main.ml`.

This keeps onboarding easy while still getting the deeper confidence benefits of model-based testing.

