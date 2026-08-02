# Eon project tasks
BENCH_NAMES := "sparse_set entity_manager query query_large world loop"
ENGINE_BENCH_NAMES := "executor render_stream prefab"
EDN_BENCH_NAMES := "edn_parser"

# Build project
build:
    opam exec -- dune build

# Run unit tests
run-tests:
    opam exec -- dune test

# Generate API documentation via odoc
docs:
    opam exec -- dune build @doc

# Build docs and open in browser
open-docs: docs
    open _build/default/_doc/_html/eon-ecs/index.html

# Run default pre-push checks
check:
    just build
    just run-tests

# Run coverage-instrumented tests and generate HTML report under _coverage/html
coverage:
    rm -rf _coverage
    mkdir -p _coverage
    BISECT_FILE="$PWD/_coverage/bisect-%p.coverage" opam exec -- dune runtest eon_ecs --instrument-with bisect_ppx --force
    opam exec -- bisect-ppx-report html --source-path . --coverage-path _coverage -o _coverage/html

# Print aggregate coverage summary from _coverage
coverage-summary:
    opam exec -- bisect-ppx-report summary --coverage-path _coverage

# Run a specific test target/alias (example: eon_ecs/test/test_main.exe or @runtest)
test suite:
    opam exec -- dune test {{suite}}

# Run a benchmark by name: sparse_set | entity_manager | query | query_large | world | loop
bench name:
    case " {{BENCH_NAMES}} " in \
      *" {{name}} "*) ;; \
      *) echo "Unknown benchmark: {{name}}"; exit 1 ;; \
    esac
    opam exec -- dune exec --profile=release eon_ecs/bench/bench_{{name}}.exe

# Run the benchmark matrix used in CI
bench-ci:
    for bench in {{BENCH_NAMES}}; do \
      just bench "$bench"; \
    done
    for bench in {{ENGINE_BENCH_NAMES}}; do \
      just engine-bench "$bench"; \
    done
    for bench in {{EDN_BENCH_NAMES}}; do \
      just edn-bench "$bench"; \
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

# Run an engine benchmark by name: executor
engine-bench name:
    case " {{ENGINE_BENCH_NAMES}} " in \
      *" {{name}} "*) ;; \
      *) echo "Unknown engine benchmark: {{name}}"; exit 1 ;; \
    esac
    opam exec -- dune exec --profile=release eon_engine/bench/bench_{{name}}.exe

# Run an eon_edn benchmark by name: edn_parser
edn-bench name:
    case " {{EDN_BENCH_NAMES}} " in \
      *" {{name}} "*) ;; \
      *) echo "Unknown eon_edn benchmark: {{name}}"; exit 1 ;; \
    esac
    opam exec -- dune exec --profile=release eon_edn/bench/bench_{{name}}.exe

# Run snake non-reactive example
snake_nonreactive:
    opam exec -- dune exec eon_ecs/examples/snake_nonreactive.exe

# Run snake reactive example
snake_reactive:
    opam exec -- dune exec eon_ecs/examples/snake_reactive.exe

# Generate codebase visualizations (docs/design/codebase_map.md)
visualizations:
    bash scripts/gen_visualizations.sh

# Clean build artifacts
clean:
    opam exec -- dune clean

# List all available tasks
tasks:
    just --list
