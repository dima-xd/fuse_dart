# Commonly used commands for fuse_dart development.
#
# Everything is runnable via `just <recipe>`; see `just --list`.

# Shared conformance is vendored as the conformance/ git submodule (init
# recursively, npm install inside once). FUSE_REPO_ROOT tells the bridge
# client which repo is running it.
export FUSE_REPO_ROOT := justfile_directory()

default:
    @just --list

# ── Quick checks ─────────────────────────────────────────────────────

# Analyze all Dart code (lib, tool, test, example, benchmark)
analyze:
    dart analyze lib tool test example benchmark

# Dart-side tests only (engine edges + bridge protocol, no Node needed)
test:
    dart test

# Manual smoke test of all major code paths
smoke:
    dart run tool/smoke.dart

# Format Nix expressions (dart fmt for Dart files)
fmt:
    dart format lib tool test example benchmark

# ── Conformance harness ──────────────────────────────────────────────

# Baseline: vendored upstream Fuse.js suite against real Fuse.js
conformance:
    cd conformance && npx vitest run

# The real thing: vendored upstream suite against fuse_dart via the bridge
bridge:
    cd conformance && FUSE_BRIDGE=dart npx vitest run

# Bridge harness tests only (process lifecycle, leaks, deadlock guards)
harness:
    cd conformance && FUSE_BRIDGE=dart npx vitest run harness

# ── Full gate (run before committing) ────────────────────────────────

# Everything: analyze + dart tests + baseline + bridge conformance
check: analyze test conformance bridge
    @echo "All green: analyze, dart tests, conformance baseline, bridge."

# ── Example & benchmarks ─────────────────────────────────────────────

# Interactive fusejs.io-style demo (pass a query for one-shot mode)
demo *ARGS:
    dart run example/demo.dart {{ARGS}}

# Performance suite (Dart-only, JIT — quick during development)
bench:
    dart run benchmark/perf_suite.dart

# Native Dart perf suite with AOT build-if-stale. The shared benchmark
# driver (conformance/benchmark/compare.mjs) invokes this so toolchain
# knowledge stays in the repo that owns it; ARGS pass through to the suite.
bench-suite *ARGS:
    #!/usr/bin/env sh
    set -eu
    case " {{ARGS}} " in
        *" --jit "*) exec dart run benchmark/perf_suite.dart {{ARGS}} ;;
    esac
    exe=.dart_tool/fuse_bench/perf_suite
    mkdir -p .dart_tool/fuse_bench
    if [ ! -x "$exe" ] || [ -n "$(find lib benchmark -name '*.dart' -newer "$exe" -print -quit 2>/dev/null)" ]; then
        echo "compiling Dart AOT binary (one-time)..." >&2
        dart compile exe benchmark/perf_suite.dart -o "$exe"
    fi
    exec "$exe" {{ARGS}}

# Cross-language benchmark via the shared driver: native fuse_dart (AOT)
# vs native Fuse.js 7.5.0. A bare run defaults to dart,js; select
# languages with --langs, e.g. `just bench-compare --langs go,dart,js`.
# Extra args pass through (--size/--samples/--warmup/--workload/--json).
bench-compare *ARGS:
    FUSE_BENCH_DEFAULT='dart,js' node conformance/benchmark/compare.mjs {{ARGS}}

# Deterministic behavior snapshot (diff across revisions)
golden:
    dart run benchmark/golden.dart

# ── Maintenance ──────────────────────────────────────────────────────

# Kill any orphaned bridge servers (the server exits with its parent via PR_SET_PDEATHSIG, so this is rarely needed)
kill-servers:
    pkill -f "tool/bridge/server.dart" || true

# Clean build/test artifacts
clean:
    rm -rf .dart_tool 2>/dev/null || true
    find . -name "*.dart_tool" -prune -o -type d -name "build" -print 2>/dev/null | xargs rm -rf 2>/dev/null || true
