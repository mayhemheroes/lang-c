#![no_main]

use arbitrary::Arbitrary;
use libfuzzer_sys::fuzz_target;

use lang_c::driver::{parse_preprocessed, Config};

#[derive(Arbitrary, Debug)]
struct Data {
    use_gcc: bool,
    source: String,
}

fuzz_target!(|data: Data| {
    let config = if data.use_gcc {
        Config::with_gcc()
    } else {
        Config::with_clang()
    };
    let _ = parse_preprocessed(&config, data.source);
});
