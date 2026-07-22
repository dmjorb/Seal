//
//  post17.rs
//  RustBridge(Minimuxer)
//
//  Shared Tokio runtime for synchronous Swift FFI entry points.
//

use once_cell::sync::Lazy;
use tokio::runtime::{self, Runtime};

pub static RUNTIME: Lazy<Runtime> = Lazy::new(|| {
    runtime::Builder::new_multi_thread()
        .enable_io()
        .enable_time()
        .build()
        .expect("unable to create Minimuxer Tokio runtime")
});
