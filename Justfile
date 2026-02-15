# Eon project tasks

# Build project
build:
    opam exec -- dune build

# Run unit tests
run-tests:
    opam exec -- dune test

# Run sparse-set benchmark (release profile recommended)
bench-sparse-set:
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_sparse_set.exe

# Run entity-manager benchmark (release profile recommended)
bench-entity-manager:
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_entity_manager.exe

# Run query benchmark (release profile recommended)
bench-query:
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_query.exe

# Run world component benchmark (release profile recommended)
bench-world:
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_world.exe

# List all available tasks
tasks:
    just --list
