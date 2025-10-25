# Eon project tasks

# Run unit tests
run-tests:
	dune test

# Run sparse-set benchmark (release profile recommended)
bench-sparse-set:
	dune exec --profile=release eon_ecs/bench/bench_sparse_set.exe
