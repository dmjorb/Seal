//
//  lib.rs
//  RustBridge(Minimuxer)
//
//  Seal uses the iOS 17+ remote-pairing implementation exclusively.
//

pub use errors::IdeviceFfiError;

pub mod bridge_idevice;
mod errors;
mod idevice_support;
mod post17;
