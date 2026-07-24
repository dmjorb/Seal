use std::ffi::{c_char, CString};

#[repr(C)]
#[derive(Debug)]
pub struct IdeviceFfiError {
    pub code: i32,
    pub message: *const c_char,
}

pub(crate) fn allocate_ffi_error(code: i32, message: String) -> *mut IdeviceFfiError {
    let sanitized = message.replace('\0', "\\0");
    let raw_message = CString::new(sanitized)
        .map(CString::into_raw)
        .unwrap_or(std::ptr::null_mut());

    Box::into_raw(Box::new(IdeviceFfiError {
        code,
        message: raw_message,
    }))
}

pub(crate) fn internal_ffi_error(message: impl Into<String>) -> *mut IdeviceFfiError {
    allocate_ffi_error(-1, message.into())
}

/// Frees an `IdeviceFfiError` allocated by this library.
///
/// # Safety
/// `err` must either be null or a pointer returned by this library.
#[no_mangle]
pub unsafe extern "C" fn idevice_error_free(err: *mut IdeviceFfiError) {
    if err.is_null() {
        return;
    }

    let error = unsafe { Box::from_raw(err) };
    if !error.message.is_null() {
        unsafe {
            let _ = CString::from_raw(error.message as *mut c_char);
        }
    }
}

#[macro_export]
macro_rules! ffi_err {
    ($err:expr) => {{
        use idevice::IdeviceError;

        let err: IdeviceError = $err.into();
        $crate::errors::allocate_ffi_error(err.code(), format!("{:?}", err))
    }};
}
