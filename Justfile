# Eon project tasks
BENCH_NAMES := "sparse_set entity_manager query world loop"

# Build project
build:
    opam exec -- dune build

# Run unit tests
run-tests:
    opam exec -- dune test

# Run default pre-push checks
check:
    just build
    just run-tests

# Run a specific test target/alias (example: eon_ecs/test/test_main.exe or @runtest)
test suite:
    opam exec -- dune test {{suite}}

# Run a benchmark by name: sparse_set | entity_manager | query | world | loop
bench name:
    case " {{BENCH_NAMES}} " in \
      *" {{name}} "*) ;; \
      *) echo "Unknown benchmark: {{name}}"; exit 1 ;; \
    esac
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_{{name}}.exe

# Run the benchmark matrix used in CI
bench-ci:
    for bench in {{BENCH_NAMES}}; do \
      just bench "$$bench"; \
    done

# Run benchmark 3 times and save outputs under /tmp
bench-compare name:
    case " {{BENCH_NAMES}} " in \
      *" {{name}} "*) ;; \
      *) echo "Unknown benchmark: {{name}}"; exit 1 ;; \
    esac
    ts="$(date +%Y%m%d-%H%M%S)"; \
    out_dir="/tmp/eon-bench-${ts}"; \
    mkdir -p "$out_dir"; \
    i=1; \
    while [ $i -le 3 ]; do \
      just bench {{name}} | tee "$out_dir/{{name}}-run$i.txt"; \
      i=$((i+1)); \
    done; \
    echo "Saved benchmark runs to $out_dir"

# Clean build artifacts
clean:
    opam exec -- dune clean

# List all available tasks
tasks:
    just --list
