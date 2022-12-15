FROM ghcr.io/evanrichter/cargo-fuzz as builder

ADD . /lang-c
WORKDIR /lang-c/fuzz
RUN cargo +nightly fuzz build 

FROM debian:bookworm
COPY --from=builder /lang-c/fuzz/target/x86_64-unknown-linux-gnu/release/langc-fuzz /