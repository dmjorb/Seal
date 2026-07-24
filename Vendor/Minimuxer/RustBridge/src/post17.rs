//
//  post17.rs
//  RustBridge(Minimuxer)
//
//  Created by Magesh K on 02/03/26.
//

// Post-17 async operations requiring idevice + tokio.

use std::io::Write;
use std::net::{Ipv4Addr, SocketAddrV4};
use std::str::FromStr;

use idevice::core_device_proxy::CoreDeviceProxy;
use idevice::debug_proxy::DebugProxyClient;
use idevice::mobile_image_mounter::ImageMounter;
use idevice::provider::{IdeviceProvider, TcpProvider};
use idevice::usbmuxd::UsbmuxdConnection;
use idevice::{IdeviceService, RsdService};
use log::{debug, error, info};
use once_cell::sync::Lazy;
use tokio::runtime::{self, Runtime};

static RUNTIME: Lazy<Option<Runtime>> = Lazy::new(|| {
    match runtime::Builder::new_multi_thread()
        .enable_io()
        .enable_time()
        .build()
    {
        Ok(runtime) => Some(runtime),
        Err(error) => {
            error!("Unable to initialize RustBridge Tokio runtime: {error}");
            None
        }
    }
});

pub(crate) fn shared_runtime() -> Option<&'static Runtime> {
    Lazy::force(&RUNTIME).as_ref()
}

async fn get_provider(muxer_addr: &str, device_ip: &str) -> Result<TcpProvider, i32> {
    let muxer_socket = SocketAddrV4::from_str(muxer_addr).map_err(|error| {
        error!("Invalid muxer address {muxer_addr}: {error}");
        1i32
    })?;
    let device_ip = Ipv4Addr::from_str(device_ip).map_err(|error| {
        error!("Invalid device IP {device_ip}: {error}");
        1i32
    })?;

    let mut uc = UsbmuxdConnection::new(
        Box::new(
            tokio::net::TcpStream::connect(muxer_socket)
                .await
                .map_err(|error| {
                    error!("Unable to connect to usbmuxd at {muxer_socket}: {error}");
                    1i32
                })?,
        ),
        0,
    );

    let dev = uc
        .get_devices()
        .await
        .ok()
        .and_then(|devices| devices.into_iter().next())
        .ok_or(1i32)?;

    let provider = dev.to_provider(
        idevice::usbmuxd::UsbmuxdAddr::TcpSocket(std::net::SocketAddr::V4(muxer_socket)),
        "asdf",
    );
    let pairing_file = provider.get_pairing_file().await.map_err(|error| {
        error!("Unable to obtain pairing file from provider: {error:?}");
        1i32
    })?;

    Ok(TcpProvider {
        addr: std::net::IpAddr::V4(device_ip),
        pairing_file,
        label: "minimuxer".to_string(),
    })
}

/// Post-17 JIT: CoreDeviceProxy → DVT → ProcessControl → DebugProxy.
/// Returns 0 on success, 1-12 on specific failures.
pub(crate) fn debug_app_post17(app_id: String, muxer_addr: String, device_ip: String) -> i32 {
    let Some(runtime) = shared_runtime() else {
        return 12;
    };

    runtime.block_on(async move {
        let provider = match get_provider(&muxer_addr, &device_ip).await {
            Ok(p) => p,
            Err(e) => return e,
        };

        let proxy = match CoreDeviceProxy::connect(&provider).await {
            Ok(p) => p,
            Err(e) => {
                error!("CoreDeviceProxy: {:?}", e);
                return 2;
            }
        };

        let rsd_port = proxy.tunnel_info().server_rsd_port;
        let adapter = match proxy.create_software_tunnel() {
            Ok(a) => a,
            Err(e) => {
                error!("SoftwareTunnel: {:?}", e);
                return 3;
            }
        };

        let mut adapter_handle = adapter.to_async_handle();
        let stream = match adapter_handle.connect(rsd_port).await {
            Ok(a) => a,
            Err(e) => {
                error!("Failed to connect to RemoteXPC port: {:?}", e);
                return 4;
            }
        };

        let mut handshake = match idevice::rsd::RsdHandshake::new(stream).await {
            Ok(x) => x,
            Err(e) => {
                error!("Failed to get handshake: {e:?}");
                return 5;
            }
        };

        let mut rs = match idevice::dvt::remote_server::RemoteServerClient::connect_rsd(
            &mut adapter_handle,
            &mut handshake,
        )
        .await
        {
            Ok(x) => x,
            Err(e) => {
                error!("Failed to connect to remote server client: {e:?}");
                return 6;
            }
        };

        let mut pc = match idevice::dvt::process_control::ProcessControlClient::new(&mut rs).await {
            Ok(p) => p,
            Err(e) => {
                error!("ProcessControl: {:?}", e);
                return 9;
            }
        };

        let pid = match pc.launch_app(app_id, None, None, true, false).await {
            Ok(p) => p,
            Err(e) => {
                error!("LaunchApp: {:?}", e);
                return 10;
            }
        };
        debug!("Launched PID {pid}");
        let _ = pc.disable_memory_limit(pid).await;

        let mut dp = match DebugProxyClient::connect_rsd(&mut adapter_handle, &mut handshake).await {
            Ok(p) => p,
            Err(e) => {
                error!("DebugProxy connect: {:?}", e);
                return 4;
            }
        };
        for cmd in [
            format!("vAttach;{pid:02X}"),
            "D".into(),
            "D".into(),
            "D".into(),
            "D".into(),
        ] {
            match dp.send_command(cmd.into()).await {
                Ok(res) => debug!("cmd res: {res:?}"),
                Err(e) => {
                    error!("DebugProxy cmd: {:?}", e);
                    return 11;
                }
            }
        }
        0
    })
}

/// Post-17 personalized DDI mount from pre-downloaded bytes.
/// Returns 0 on success, 1-9 on specific failures.
pub(crate) fn mount_personalized_ddi(
    image_bytes: &[u8],
    trustcache_bytes: &[u8],
    manifest_bytes: &[u8],
    muxer_addr: String,
    device_ip: String,
) -> i32 {
    let Some(runtime) = shared_runtime() else {
        return 9;
    };

    runtime.block_on(async move {
        let provider = match get_provider(&muxer_addr, &device_ip).await {
            Ok(p) => p,
            Err(e) => return e,
        };

        let mut lockdown = match idevice::lockdown::LockdownClient::connect(&provider).await {
            Ok(l) => l,
            Err(e) => {
                error!("Lockdown connect: {:?}", e);
                return 4;
            }
        };

        let ucid_val = match lockdown.get_value(Some("UniqueChipID"), None).await {
            Ok(u) => u,
            Err(_) => {
                let pairing_file = match provider.get_pairing_file().await {
                    Ok(pairing_file) => pairing_file,
                    Err(e) => {
                        error!("Unable to read pairing file: {e:?}");
                        return 4;
                    }
                };
                if let Err(e) = lockdown.start_session(&pairing_file).await {
                    error!("Session: {:?}", e);
                    return 4;
                }
                match lockdown.get_value(Some("UniqueChipID"), None).await {
                    Ok(l) => l,
                    Err(e) => {
                        error!("UniqueChipID: {:?}", e);
                        return 5;
                    }
                }
            }
        };
        let unique_chip_id = match ucid_val.as_unsigned_integer() {
            Some(i) => i,
            None => {
                error!("UniqueChipID not int");
                return 5;
            }
        };

        let mut mounter = match ImageMounter::connect(&provider).await {
            Ok(m) => m,
            Err(e) => {
                error!("ImageMounter: {:?}", e);
                return 6;
            }
        };

        let images = match mounter.copy_devices().await {
            Ok(i) => i,
            Err(e) => {
                error!("copy_devices: {:?}", e);
                return 6;
            }
        };
        if !images.is_empty() {
            info!("Already mounted");
            return 0;
        }

        info!("Mounting personalized DDI...");
        if let Err(e) = mounter
            .mount_personalized_with_callback(
                &provider,
                image_bytes.to_vec(),
                trustcache_bytes.to_vec(),
                manifest_bytes,
                None,
                unique_chip_id,
                async |((n, d), _)| {
                    if d > 0 {
                        let pct = (n as f64 / d as f64) * 100.0;
                        print!("\rProgress: {pct:.2}%");
                        let _ = std::io::stdout().flush();
                    }
                    if n == d {
                        println!();
                    }
                },
                (),
            )
            .await
        {
            error!("Mount failed: {:?}", e);
            return 8;
        }

        info!("DDI mounted");
        0
    })
}
