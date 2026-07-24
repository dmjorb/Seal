//
//  bridge.rs
//  RustBridge(Minimuxer)
//
//  Created by Magesh K on 02/03/26.
//

use crate::post17;
use plist_plus::Plist;
use rusty_libimobiledevice::idevice::{get_first_device, Device};
use rusty_libimobiledevice::services::afc::{AfcClient, AfcFileMode};
use rusty_libimobiledevice::services::debug_server::DebugServer;
use rusty_libimobiledevice::services::heartbeat::HeartbeatClient;
use rusty_libimobiledevice::services::instproxy::InstProxyClient;
use rusty_libimobiledevice::services::lockdownd::LockdowndClient;
use rusty_libimobiledevice::services::misagent::MisagentClient;
use rusty_libimobiledevice::services::mobile_image_mounter::MobileImageMounter;
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

fn to_char(s: String) -> *mut c_char {
    CString::new(s)
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

#[no_mangle]
pub extern "C" fn rust_bridge_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        unsafe {
            let _ = CString::from_raw(ptr);
        }
    }
}

// --- Device ---
pub struct DeviceWrapper(Device);

#[no_mangle]
pub extern "C" fn rust_bridge_device_free(ptr: *mut DeviceWrapper) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_device_get_first() -> *mut DeviceWrapper {
    match get_first_device() {
        Ok(d) => Box::into_raw(Box::new(DeviceWrapper(d))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_device_get_udid(device: *mut DeviceWrapper) -> *mut c_char {
    let Some(d) = (unsafe { device.as_ref() }) else {
        return std::ptr::null_mut();
    };
    to_char(d.0.get_udid())
}

// --- Lockdown ---
pub struct LockdownWrapper<'a>(LockdowndClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_lockdown_free(ptr: *mut LockdownWrapper<'static>) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_lockdown_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut LockdownWrapper<'static> {
    let Some(d) = (unsafe { device.as_ref() }) else {
        return std::ptr::null_mut();
    };
    let Some(label) = c_string_arg(label) else {
        return std::ptr::null_mut();
    };
    unsafe {
        match d.0.new_lockdownd_client(&label) {
            Ok(c) => Box::into_raw(Box::new(LockdownWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_lockdown_get_value(
    client: *mut LockdownWrapper,
    domain: *const c_char,
    key: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else {
        return std::ptr::null_mut();
    };
    let domain_storage = if domain.is_null() {
        None
    } else {
        let Some(value) = c_string_arg(domain) else {
            return std::ptr::null_mut();
        };
        Some(value)
    };
    let Some(key) = c_string_arg(key) else {
        return std::ptr::null_mut();
    };
    let domain = domain_storage.as_deref().unwrap_or("");
    match c.0.get_value(&key, domain) {
        Ok(p) => match p.get_string_val() {
            Ok(s) => to_char(s),
            Err(_) => to_char(p.to_string()),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

// --- AFC ---
pub struct AfcWrapper<'a>(AfcClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_afc_free(ptr: *mut AfcWrapper<'static>) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut AfcWrapper<'static> {
    let Some(d) = (unsafe { device.as_ref() }) else {
        return std::ptr::null_mut();
    };
    let Some(label) = c_string_arg(label) else {
        return std::ptr::null_mut();
    };
    unsafe {
        match d.0.new_afc_client(&label) {
            Ok(c) => Box::into_raw(Box::new(AfcWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_remove(client: *mut AfcWrapper, path: *const c_char) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(path) = c_string_arg(path) else { return false; };
    c.0.remove_path_and_contents(&path).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_mkdir(client: *mut AfcWrapper, path: *const c_char) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(path) = c_string_arg(path) else { return false; };
    c.0.make_directory(&path).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_open(
    client: *mut AfcWrapper,
    path: *const c_char,
    mode: *const c_char,
) -> u64 {
    let Some(c) = (unsafe { client.as_ref() }) else { return 0; };
    let Some(path) = c_string_arg(path) else { return 0; };
    let Some(mode_str) = c_string_arg(mode) else { return 0; };
    let mode = match mode_str.as_str() {
        "r" | "rdonly" => AfcFileMode::ReadOnly,
        "w" | "wronly" => AfcFileMode::WriteOnly,
        "rw" | "rdwr" => AfcFileMode::ReadWrite,
        _ => return 0,
    };
    match c.0.file_open(&path, mode) {
        Ok(handle) => handle,
        Err(_) => 0,
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_write(
    client: *mut AfcWrapper,
    handle: u64,
    data: *const u8,
    size: u32,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(data) = bytes_arg(data, size) else { return false; };
    c.0.file_write(handle, data.to_vec()).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_read(
    client: *mut AfcWrapper,
    handle: u64,
    size: u32,
    out_len: *mut u32,
) -> *mut u8 {
    if out_len.is_null() {
        return std::ptr::null_mut();
    }
    unsafe { *out_len = 0; }
    let Some(c) = (unsafe { client.as_ref() }) else {
        return std::ptr::null_mut();
    };
    match c.0.file_read(handle, size) {
        Ok(data) => {
            let data: Vec<u8> = data.into_iter().map(|b| b as u8).collect();
            if data.is_empty() {
                return std::ptr::null_mut();
            }
            let Ok(len) = u32::try_from(data.len()) else {
                return std::ptr::null_mut();
            };
            let mut boxed = data.into_boxed_slice();
            let ptr = boxed.as_mut_ptr();
            unsafe { *out_len = len; }
            std::mem::forget(boxed);
            ptr
        }
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_free_byte_array(ptr: *mut u8, len: u32) {
    if ptr.is_null() || len == 0 {
        return;
    }
    unsafe {
        let slice = std::ptr::slice_from_raw_parts_mut(ptr, len as usize);
        drop(Box::<[u8]>::from_raw(slice));
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_file_close(client: *mut AfcWrapper, handle: u64) {
    if let Some(c) = unsafe { client.as_ref() } {
        let _ = c.0.file_close(handle);
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_get_file_info(
    client: *mut AfcWrapper,
    path: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(path) = c_string_arg(path) else { return std::ptr::null_mut(); };
    match c.0.get_file_info(&path) {
        Ok(info) => match serde_json::to_string(&info) {
            Ok(json) => to_char(json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_afc_read_directory(
    client: *mut AfcWrapper,
    path: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(path) = c_string_arg(path) else { return std::ptr::null_mut(); };
    match c.0.read_directory(&path) {
        Ok(entries) => match serde_json::to_string(&entries) {
            Ok(json) => to_char(json),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

// --- InstProxy ---
pub struct InstProxyWrapper<'a>(InstProxyClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_free(ptr: *mut InstProxyWrapper<'static>) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut InstProxyWrapper<'static> {
    let Some(d) = (unsafe { device.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(label) = c_string_arg(label) else { return std::ptr::null_mut(); };
    unsafe {
        match d.0.new_instproxy_client(&label) {
            Ok(c) => Box::into_raw(Box::new(InstProxyWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_install(
    client: *mut InstProxyWrapper,
    path: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(path) = c_string_arg(path) else { return false; };
    c.0.install(&path, None).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_uninstall(
    client: *mut InstProxyWrapper,
    bundle_id: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(bundle_id) = c_string_arg(bundle_id) else { return false; };
    c.0.uninstall(&bundle_id, None).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_lookup(
    client: *mut InstProxyWrapper,
    app_id: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(app_id) = c_string_arg(app_id) else { return std::ptr::null_mut(); };
    let client_opts = InstProxyClient::create_return_attributes(
        vec![("ApplicationType".to_string(), Plist::new_string("Any"))],
        vec![
            "CFBundleIdentifier".to_string(),
            "CFBundleExecutable".to_string(),
            "CFBundlePath".to_string(),
            "BundlePath".to_string(),
            "Container".to_string(),
        ],
    );
    match c.0.lookup(vec![app_id.clone()], Some(client_opts)) {
        Ok(result) => match result.dict_get_item(&app_id) {
            Ok(app_data) => to_char(app_data.to_string()),
            Err(_) => std::ptr::null_mut(),
        },
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_instproxy_get_path_for_bundle_identifier(
    client: *mut InstProxyWrapper,
    bundle_id: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(bundle_id) = c_string_arg(bundle_id) else { return std::ptr::null_mut(); };
    match c.0.get_path_for_bundle_identifier(bundle_id) {
        Ok(path) => to_char(path),
        Err(_) => std::ptr::null_mut(),
    }
}

// --- Misagent ---
pub struct MisagentWrapper<'a>(MisagentClient<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_free(ptr: *mut MisagentWrapper<'static>) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut MisagentWrapper<'static> {
    let Some(d) = (unsafe { device.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(label) = c_string_arg(label) else { return std::ptr::null_mut(); };
    unsafe {
        match d.0.new_misagent_client(&label) {
            Ok(c) => Box::into_raw(Box::new(MisagentWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_install(
    client: *mut MisagentWrapper,
    profile_ptr: *const u8,
    size: u32,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(data) = bytes_arg(profile_ptr, size) else { return false; };
    c.0.install(Plist::new_data(data)).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_remove(
    client: *mut MisagentWrapper,
    profile_id: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(profile_id) = c_string_arg(profile_id) else { return false; };
    c.0.remove(profile_id).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_misagent_copy_all(client: *mut MisagentWrapper) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    match c.0.copy(false) {
        Ok(p) => to_char(Plist::from(p).to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

// --- Debugserver ---
pub struct DebugserverWrapper<'a>(DebugServer<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_free(ptr: *mut DebugserverWrapper<'static>) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut DebugserverWrapper<'static> {
    let Some(d) = (unsafe { device.as_ref() }) else { return std::ptr::null_mut(); };
    if c_string_arg(label).is_none() {
        return std::ptr::null_mut();
    }
    unsafe {
        match d.0.new_debug_server("minimuxer") {
            Ok(c) => Box::into_raw(Box::new(DebugserverWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_send_command(
    client: *mut DebugserverWrapper,
    command: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(command) = c_string_arg(command) else { return std::ptr::null_mut(); };
    match c.0.send_command(command.into()) {
        Ok(res) => to_char(format!("{:?}", res)),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_debugserver_set_argv(
    client: *mut DebugserverWrapper,
    argv_json: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(argv_str) = c_string_arg(argv_json) else { return false; };
    let argv: Vec<String> = match serde_json::from_str(&argv_str) {
        Ok(v) => v,
        Err(_) => return false,
    };
    c.0.set_argv(argv).is_ok()
}

// --- MobileImageMounter ---
pub struct MounterWrapper<'a>(MobileImageMounter<'a>);

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_free(ptr: *mut MounterWrapper<'static>) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut MounterWrapper<'static> {
    let Some(d) = (unsafe { device.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(label) = c_string_arg(label) else { return std::ptr::null_mut(); };
    unsafe {
        match d.0.new_mobile_image_mounter(&label) {
            Ok(c) => Box::into_raw(Box::new(MounterWrapper(std::mem::transmute(c)))),
            Err(_) => std::ptr::null_mut(),
        }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_lookup(
    client: *mut MounterWrapper,
    image_type: *const c_char,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(image_type) = c_string_arg(image_type) else { return std::ptr::null_mut(); };
    match c.0.lookup_image(&image_type) {
        Ok(p) => to_char(Plist::from(p).to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_upload(
    client: *mut MounterWrapper,
    path: *const c_char,
    signature: *const c_char,
    image_type: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(path) = c_string_arg(path) else { return false; };
    let Some(signature) = c_string_arg(signature) else { return false; };
    let Some(image_type) = c_string_arg(image_type) else { return false; };
    c.0.upload_image(&path, &image_type, &signature).is_ok()
}

#[no_mangle]
pub extern "C" fn rust_bridge_mounter_mount(
    client: *mut MounterWrapper,
    path: *const c_char,
    signature: *const c_char,
    image_type: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(path) = c_string_arg(path) else { return false; };
    let Some(signature) = c_string_arg(signature) else { return false; };
    let Some(image_type) = c_string_arg(image_type) else { return false; };
    c.0.mount_image(&path, &image_type, &signature).is_ok()
}

// --- Heartbeat ---
pub struct HeartbeatWrapper(HeartbeatClient);

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_free(ptr: *mut HeartbeatWrapper) {
    if !ptr.is_null() {
        unsafe { drop(Box::from_raw(ptr)); }
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_new(
    device: *mut DeviceWrapper,
    label: *const c_char,
) -> *mut HeartbeatWrapper {
    let Some(d) = (unsafe { device.as_ref() }) else { return std::ptr::null_mut(); };
    let Some(label) = c_string_arg(label) else { return std::ptr::null_mut(); };
    match d.0.new_heartbeat_client(&label) {
        Ok(c) => Box::into_raw(Box::new(HeartbeatWrapper(c))),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_receive(
    client: *mut HeartbeatWrapper,
    timeout_ms: u32,
) -> *mut c_char {
    let Some(c) = (unsafe { client.as_ref() }) else { return std::ptr::null_mut(); };
    match c.0.receive(timeout_ms) {
        Ok(p) => to_char(Plist::from(p).to_string()),
        Err(_) => std::ptr::null_mut(),
    }
}

#[no_mangle]
pub extern "C" fn rust_bridge_heartbeat_send(
    client: *mut HeartbeatWrapper,
    plist_xml: *const c_char,
) -> bool {
    let Some(c) = (unsafe { client.as_ref() }) else { return false; };
    let Some(xml) = c_string_arg(plist_xml) else { return false; };
    let p = match Plist::from_xml(xml) {
        Ok(p) => p,
        Err(_) => return false,
    };
    c.0.send(p).is_ok()
}

// --- Utility ---

#[no_mangle]
pub extern "C" fn rust_bridge_set_debug(level: i32) {
    extern "C" {
        fn libusbmuxd_set_debug_level(level: i32);
        fn idevice_set_debug_level(level: i32);
    }
    unsafe {
        libusbmuxd_set_debug_level(level);
        idevice_set_debug_level(level);
    }
}

// --- Post-17 (delegates to post17.rs) ---

#[no_mangle]
pub extern "C" fn rust_bridge_debug_app_post17(
    app_id: *const c_char,
    muxer_addr: *const c_char,
    device_ip: *const c_char,
) -> i32 {
    let Some(app_id) = c_string_arg(app_id) else { return 1; };
    let Some(muxer_addr) = c_string_arg(muxer_addr) else { return 1; };
    let Some(device_ip) = c_string_arg(device_ip) else { return 1; };
    post17::debug_app_post17(app_id, muxer_addr, device_ip)
}

#[no_mangle]
pub extern "C" fn rust_bridge_mount_personalized_ddi(
    image_ptr: *const u8,
    image_len: u32,
    trustcache_ptr: *const u8,
    trustcache_len: u32,
    manifest_ptr: *const u8,
    manifest_len: u32,
    muxer_addr: *const c_char,
    device_ip: *const c_char,
) -> i32 {
    let Some(image) = bytes_arg(image_ptr, image_len) else { return 1; };
    let Some(trustcache) = bytes_arg(trustcache_ptr, trustcache_len) else { return 1; };
    let Some(manifest) = bytes_arg(manifest_ptr, manifest_len) else { return 1; };
    let Some(muxer_addr) = c_string_arg(muxer_addr) else { return 1; };
    let Some(device_ip) = c_string_arg(device_ip) else { return 1; };
    post17::mount_personalized_ddi(image, trustcache, manifest, muxer_addr, device_ip)
}
