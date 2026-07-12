#![no_main]
use libfuzzer_sys::fuzz_target;
use lang_c::driver::{Config, parse_preprocessed}; 
use std::str;

fuzz_target!(|data: &[u8]| {
    // fuzzed code goes here
    match str::from_utf8(data) {
        Ok(in_string)=>{
            let config = Config::default();
            parse_preprocessed(&config, in_string.to_string());
        },
        Err(..)=>()
    }
});
