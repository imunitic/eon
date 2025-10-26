# Eon project tasks

# Run unit tests
run-tests:
	opam exec -- dune test

# Run sparse-set benchmark (release profile recommended)
bench-sparse-set:
	opam exec -- dune exec --profile=release eon_ecs/bench/bench_sparse_set.exe

# List all available tasks
tasks:
	just --list
