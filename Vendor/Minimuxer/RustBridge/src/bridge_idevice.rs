use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::idevice_support::mounter::mount_personalized_ddi_rppairing;
use crate::idevice_support::rsd::{
    clear_rppairing_state, has_cached_rsd_connection, has_rppairing_file,
    rppairing_generation, set_rppairing_file,
};
use crate::idevice_support::{
    device::{fetch_udid_rppairing, test_device_connection},
    install::{install_ipa_rppairing, remove_app_rppairing, yeet_app_afc_rppairing},
    jit::{debug_app_rppairing, debug_process_rppairing},
    provision::{
        dump_provisioning_profile_rppairing, install_provisioning_profile_rppairing,
        remove_provisioning_profile_rppairing,
    },
};
use crate::IdeviceFfiError;
use crate::post17::RUNTIME;

fn to_char(value: String) -> *mut c_char {
    CString::new(value).unwrap().into_raw()
}

fn ffi_bytes<'a>(ptr: *const u8, len: u32) -> Result<&'a [u8], idevice::IdeviceError> {
    if len == 0 {
        return Ok(&[]);
    }
    if ptr.is_null() {
        return Err(idevice::IdeviceError::InvalidArgument);
    }
    Ok(unsafe { std::slice::from_raw_parts(ptr, len as usize) })
}

fn ffi_string(ptr: *const c_char) -> Result<String, idevice::IdeviceError> {
    if ptr.is_null() {
        return Err(idevice::IdeviceError::InvalidArgument);
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .map(str::to_owned)
        .map_err(|_| idevice::IdeviceError::InvalidArgument)
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_test_device_connection() -> bool {
    test_device_connection()
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_fetch_udid(
    udid_out: *mut *mut c_char,
) -> *mut IdeviceFfiError {
    if udid_out.is_null() {
        return crate::ffi_err!(idevice::IdeviceError::InvalidArgument);
    }

    unsafe {
        *udid_out = std::ptr::null_mut();
    }

    match RUNTIME.block_on(fetch_udid_rppairing()) {
        Ok(udid) => {
            unsafe {
                *udid_out = to_char(udid);
            }
            std::ptr::null_mut()
        }
        Err(err) => crate::ffi_err!(err),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_yeet_app_afc(
    bundle_id: *const c_char,
    ipa_ptr: *const u8,
    ipa_len: u32,
) -> *mut IdeviceFfiError {
    let bundle_id = match ffi_string(bundle_id) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    let ipa_bytes = match ffi_bytes(ipa_ptr, ipa_len) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };

    RUNTIME.block_on(async move {
        match yeet_app_afc_rppairing(bundle_id, ipa_bytes).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_install_ipa(
    bundle_id: *const c_char,
) -> *mut IdeviceFfiError {
    let bundle_id = match ffi_string(bundle_id) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    RUNTIME.block_on(async move {
        match install_ipa_rppairing(bundle_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_remove_app(bundle_id: *const c_char) -> *mut IdeviceFfiError {
    let bundle_id = match ffi_string(bundle_id) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    RUNTIME.block_on(async move {
        match remove_app_rppairing(bundle_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_debug_app(app_id: *const c_char) -> *mut IdeviceFfiError {
    let app_id = match ffi_string(app_id) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    RUNTIME.block_on(async move {
        match debug_app_rppairing(app_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_debug_process(pid: u32) -> *mut IdeviceFfiError {
    RUNTIME.block_on(async move {
        match debug_process_rppairing(pid).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_install_provisioning_profile(
    profile_ptr: *const u8,
    profile_len: u32,
) -> *mut IdeviceFfiError {
    let profile = match ffi_bytes(profile_ptr, profile_len) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    RUNTIME.block_on(async move {
        match install_provisioning_profile_rppairing(profile).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_remove_provisioning_profile(
    id: *const c_char,
) -> *mut IdeviceFfiError {
    let id = match ffi_string(id) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    RUNTIME.block_on(async move {
        match remove_provisioning_profile_rppairing(id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_dump_provisioning_profile(
    docs_path: *const c_char,
) -> *mut IdeviceFfiError {
    let docs_path = match ffi_string(docs_path) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };
    RUNTIME.block_on(async move {
        match dump_provisioning_profile_rppairing(docs_path).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_set_rppairing_file(
    pairing_file: *const c_char,
) -> *mut IdeviceFfiError {
    let pairing_file_str = match ffi_string(pairing_file) {
        Ok(value) => value,
        Err(err) => return crate::ffi_err!(err),
    };

    match set_rppairing_file(pairing_file_str) {
        Ok(()) => std::ptr::null_mut(),
        Err(err) => crate::ffi_err!(err),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_clear_rppairing_state() {
    clear_rppairing_state();
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_has_rppairing_file() -> bool {
    has_rppairing_file()
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_has_cached_rsd_connection() -> bool {
    has_cached_rsd_connection()
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_rppairing_generation() -> u64 {
    rppairing_generation()
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_mount_personalized_ddi(
    image_ptr: *const u8,
    image_len: u32,
    trustcache_ptr: *const u8,
    trustcache_len: u32,
    manifest_ptr: *const u8,
    manifest_len: u32,
) -> i32 {
    let image = match ffi_bytes(image_ptr, image_len) {
        Ok(value) => value,
        Err(err) => return err.code(),
    };
    let trustcache = match ffi_bytes(trustcache_ptr, trustcache_len) {
        Ok(value) => value,
        Err(err) => return err.code(),
    };
    let manifest = match ffi_bytes(manifest_ptr, manifest_len) {
        Ok(value) => value,
        Err(err) => return err.code(),
    };
    RUNTIME.block_on(async move {
        mount_personalized_ddi_rppairing(image, trustcache, manifest).await
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn null_bytes_are_valid_only_for_zero_length() {
        assert!(ffi_bytes(std::ptr::null(), 0).unwrap().is_empty());
        assert!(ffi_bytes(std::ptr::null(), 1).is_err());
    }

    #[test]
    fn null_c_string_is_rejected() {
        assert!(ffi_string(std::ptr::null()).is_err());
    }
}
