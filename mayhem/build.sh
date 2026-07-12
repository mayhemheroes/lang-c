#!/usr/bin/env bash
#
# lang-c/mayhem/build.sh — build vickenty/lang-c's cargo-fuzz target as a sanitized libFuzzer
# binary (OSS-Fuzz Rust path: cargo-fuzz + ASan via RUSTFLAGS), plus the crate's own test
# suite (normal flags) so mayhem/test.sh only RUNS it.
#
# lang-c is a pure-Rust lightweight C parser (rust-peg grammar, pre-generated src/parser.rs).
# The fuzz harness (mayhem/fuzz/fuzz_targets/langc-fuzz.rs, ported from the fork's original
# fuzz/ crate) feeds arbitrary UTF-8 to driver::parse_preprocessed.
#
# AIR-GAPPED CONTRACT (SPEC §6.5): this first (online) build populates the cargo registry under
# $CARGO_HOME=/opt/toolchains/rust/cargo; the PATCH tier re-runs this script OFFLINE with
# CARGO_NET_OFFLINE=true and resolves crates from that cache.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' — must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${MAYHEM_JOBS:=$(nproc)}"
export MAYHEM_JOBS
# cargo-fuzz has no --jobs flag; cargo reads parallelism from CARGO_BUILD_JOBS.
export CARGO_BUILD_JOBS="$MAYHEM_JOBS"

# DWARF < 4 debug-info contract (§6.2 item 10): force DWARF 2 for the Rust CUs.
: "${RUST_DEBUG_FLAGS:=-C debuginfo=2 -C force-frame-pointers=yes -C llvm-args=--dwarf-version=2}"

cd "$SRC"

# ── DWARF < 4 enforcement ──────────────────────────────────────────────────────────────────────
# Rust's ASan runtime is compiled with the nightly's bundled LLVM (DWARF 5 default) and is linked
# before project code; strip its debug sections so the binary's .debug_info stays < DWARF 4.
ASAN_RT="$(find "$RUSTUP_HOME/toolchains" -name "librustc-nightly_rt.asan.a" 2>/dev/null | head -1)"
if [ -n "$ASAN_RT" ] && [ -f "$ASAN_RT" ]; then
    echo "Stripping debug info from Rust ASan runtime to enforce DWARF < 4: $ASAN_RT"
    objcopy --strip-debug "$ASAN_RT"
fi

# libfuzzer-sys compiles libFuzzer from C++ via the cc crate; force DWARF 3 for those CUs too.
export CFLAGS="${CFLAGS:+$CFLAGS }-gdwarf-3"
export CXXFLAGS="${CXXFLAGS:+$CXXFLAGS }-gdwarf-3"

FUZZ_DIR="mayhem/fuzz"
FUZZ_TARGETS=(langc-fuzz)
TRIPLE="x86_64-unknown-linux-gnu"

# OSS-Fuzz Rust libFuzzer+ASan flags: --cfg fuzzing matches libfuzzer-sys; ASan via RUSTFLAGS
# (rustc ignores clang's $SANITIZER_FLAGS). RUST_DEBUG_FLAGS pins DWARF ≤ 3 for our CUs.
SAVED_RUSTFLAGS="${RUSTFLAGS:-}"
export RUSTFLAGS="${SAVED_RUSTFLAGS} --cfg fuzzing -Zsanitizer=address ${RUST_DEBUG_FLAGS}"

echo "=== cargo fuzz build (image-default nightly toolchain, ASan via RUSTFLAGS) ==="
echo "RUSTFLAGS=$RUSTFLAGS"

# Use the image's DEFAULT toolchain (Dockerfile pins it); a `+toolchain` override would make
# rustup try to install a different channel into the shared /opt/toolchains/rust.
for t in "${FUZZ_TARGETS[@]}"; do
  echo "--- building fuzz target: $t ---"
  cargo fuzz build --fuzz-dir "$FUZZ_DIR" -O --debug-assertions "$t"
  bin="$SRC/$FUZZ_DIR/target/$TRIPLE/release/$t"
  [ -x "$bin" ] || { echo "ERROR: expected fuzz binary not found at $bin" >&2; exit 1; }
  cp "$bin" "/mayhem/$t"
  echo "built /mayhem/$t"
done

# ── Build the crate's OWN test suite with its NORMAL flags (no sanitizers) ─────────────────────
# cargo test compiles the lib + #[test] fns (incl. the reftests/ golden-output runner in
# src/tests.rs). mayhem/test.sh then RUNS this pre-built suite; the offline PATCH re-run reuses
# the same cache (RUSTFLAGS must match here and in test.sh: both empty).
echo "=== building the upstream test suite (cargo test --no-run, normal flags) ==="
RUSTFLAGS="" cargo test --no-run --jobs "$MAYHEM_JOBS"

echo "build.sh complete:"
ls -la /mayhem/langc-fuzz
