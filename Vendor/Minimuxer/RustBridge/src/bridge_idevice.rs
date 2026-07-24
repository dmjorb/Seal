use std::ffi::{CStr, CString};
use std::os::raw::c_char;

use crate::idevice_support::mounter::mount_personalized_ddi_rppairing;
use crate::idevice_support::rsd::set_rppairing_file;
use crate::idevice_support::{
    device::{fetch_udid_rppairing, test_device_connection},
    install::{install_ipa_rppairing, remove_app_rppairing, yeet_app_afc_rppairing},
    jit::{debug_app_rppairing, debug_process_rppairing},
    provision::{
        dump_provisioning_profile_rppairing, install_provisioning_profile_rppairing,
        remove_provisioning_profile_rppairing,
    },
};
use crate::post17::shared_runtime;
use crate::IdeviceFfiError;

fn to_char(value: String) -> *mut c_char {
    CString::new(value)
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut())
}

fn c_string_arg(ptr: *const c_char) -> Option<String> {
    if ptr.is_null() {
        return None;
    }
    unsafe { CStr::from_ptr(ptr) }
        .to_str()
        .ok()
        .map(ToOwned::to_owned)
}

fn bytes_arg<'a>(ptr: *const u8, len: u32) -> Option<&'a [u8]> {
    if len == 0 {
        return Some(&[]);
    }
    if ptr.is_null() {
        return None;
    }
    Some(unsafe { std::slice::from_raw_parts(ptr, len as usize) })
}

fn invalid_argument_error() -> *mut IdeviceFfiError {
    crate::ffi_err!(IdeviceError::InvalidArgument)
}

fn runtime_error() -> *mut IdeviceFfiError {
    crate::errors::internal_ffi_error("RustBridge async runtime is unavailable")
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
        return invalid_argument_error();
    }

    unsafe {
        *udid_out = std::ptr::null_mut();
    }

    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    match runtime.block_on(fetch_udid_rppairing()) {
        Ok(udid) => {
            let pointer = to_char(udid);
            if pointer.is_null() {
                return crate::errors::internal_ffi_error("Unable to encode device UDID");
            }
            unsafe {
                *udid_out = pointer;
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
    let Some(bundle_id) = c_string_arg(bundle_id) else {
        return invalid_argument_error();
    };
    let Some(ipa_bytes) = bytes_arg(ipa_ptr, ipa_len) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
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
    let Some(bundle_id) = c_string_arg(bundle_id) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
        match install_ipa_rppairing(bundle_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_remove_app(bundle_id: *const c_char) -> *mut IdeviceFfiError {
    let Some(bundle_id) = c_string_arg(bundle_id) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
        match remove_app_rppairing(bundle_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_debug_app(app_id: *const c_char) -> *mut IdeviceFfiError {
    let Some(app_id) = c_string_arg(app_id) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
        match debug_app_rppairing(app_id).await {
            Ok(()) => std::ptr::null_mut(),
            Err(err) => crate::ffi_err!(err),
        }
    })
}

#[no_mangle]
pub extern "C" fn rust_bridge_idevice_debug_process(pid: u32) -> *mut IdeviceFfiError {
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
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
    let Some(profile) = bytes_arg(profile_ptr, profile_len) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
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
    let Some(id) = c_string_arg(id) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
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
    let Some(docs_path) = c_string_arg(docs_path) else {
        return invalid_argument_error();
    };
    let Some(runtime) = shared_runtime() else {
        return runtime_error();
    };

    runtime.block_on(async move {
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
    let Some(pairing_file) = c_string_arg(pairing_file) else {
        return invalid_argument_error();
    };

    match set_rppairing_file(pairing_file) {
        Ok(()) => std::ptr::null_mut(),
        Err(err) => crate::ffi_err!(err),
    }
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
    let Some(image) = bytes_arg(image_ptr, image_len) else { return 1; };
    let Some(trustcache) = bytes_arg(trustcache_ptr, trustcache_len) else { return 1; };
    let Some(manifest) = bytes_arg(manifest_ptr, manifest_len) else { return 1; };
    let Some(runtime) = shared_runtime() else { return 9; };

    runtime.block_on(async move {
        mount_personalized_ddi_rppairing(image, trustcache, manifest).await
    })
}
