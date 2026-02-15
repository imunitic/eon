# Eon project tasks

# Build project
build:
    opam exec -- dune build

# Run unit tests
run-tests:
    opam exec -- dune test

# Run a benchmark by name: sparse_set | entity_manager | query | world
bench name:
    case "{{name}}" in \
      sparse_set|entity_manager|query|world) ;; \
      *) echo "Unknown benchmark: {{name}}"; exit 1 ;; \
    esac
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_{{name}}.exe

# Run all benchmarks (release profile recommended)
bench-all:
    just bench sparse_set
    just bench entity_manager
    just bench query
    just bench world

# List all available tasks
tasks:
    just --list
