use idevice::{
    heartbeat::HeartbeatClient,
    remote_pairing::{RemotePairingClient, RpPairingSocket},
    rsd::RsdHandshake,
    IdeviceError, RsdService,
};

use log::{error, info};
use once_cell::sync::Lazy;

use std::{
    net::SocketAddrV4,
    ops::{Deref, DerefMut},
    str::FromStr,
    sync::Mutex,
};

type RsdAdapter = idevice::tcp::handle::AdapterHandle;

pub struct CachedRsdConnection {
    pub adapter: RsdAdapter,
    pub handshake: RsdHandshake,
}

struct GenerationOwner<T> {
    value: T,
    generation: u64,
}

struct GenerationCache<T> {
    value: Option<T>,
    generation: u64,
}

impl<T> GenerationCache<T> {
    fn new() -> Self {
        Self {
            value: None,
            generation: 0,
        }
    }

    #[cfg(test)]
    fn with_value(value: T) -> Self {
        Self {
            value: Some(value),
            generation: 0,
        }
    }

    fn checkout(&mut self) -> Option<GenerationOwner<T>> {
        self.value.take().map(|value| GenerationOwner {
            value,
            generation: self.generation,
        })
    }

    fn invalidate(&mut self) {
        self.generation = self.generation.wrapping_add(1);
        self.value.take();
    }

    fn store_if_current(&mut self, owner: GenerationOwner<T>) -> bool {
        if owner.generation != self.generation || self.value.is_some() {
            return false;
        }
        self.value = Some(owner.value);
        true
    }
}

struct PairingState {
    pairing_file: Option<idevice::remote_pairing::RpPairingFile>,
    connections: GenerationCache<CachedRsdConnection>,
}

impl PairingState {
    fn new() -> Self {
        Self {
            pairing_file: None,
            connections: GenerationCache::new(),
        }
    }
}

static RPPAIRING_STATE: Lazy<Mutex<PairingState>> =
    Lazy::new(|| Mutex::new(PairingState::new()));

pub struct OwnedRsdConnection(GenerationOwner<CachedRsdConnection>);

impl Deref for OwnedRsdConnection {
    type Target = CachedRsdConnection;

    fn deref(&self) -> &Self::Target {
        &self.0.value
    }
}

impl DerefMut for OwnedRsdConnection {
    fn deref_mut(&mut self) -> &mut Self::Target {
        &mut self.0.value
    }
}

pub fn set_rppairing_file(pairing_file_string: String) -> Result<(), IdeviceError> {
    let pairing_file =
        idevice::remote_pairing::RpPairingFile::from_bytes(pairing_file_string.as_bytes())?;

    let mut state = RPPAIRING_STATE.lock().unwrap();
    state.pairing_file = Some(pairing_file);
    state.connections.invalidate();

    Ok(())
}

pub fn clear_rppairing_state() {
    let mut state = RPPAIRING_STATE.lock().unwrap();
    state.pairing_file.take();
    state.connections.invalidate();
}

pub fn has_rppairing_file() -> bool {
    RPPAIRING_STATE.lock().unwrap().pairing_file.is_some()
}

pub fn has_cached_rsd_connection() -> bool {
    RPPAIRING_STATE
        .lock()
        .unwrap()
        .connections
        .value
        .is_some()
}

pub fn rppairing_generation() -> u64 {
    RPPAIRING_STATE.lock().unwrap().connections.generation
}

fn checkout_connection(
) -> (
    Option<OwnedRsdConnection>,
    Option<idevice::remote_pairing::RpPairingFile>,
    u64,
) {
    let mut state = RPPAIRING_STATE.lock().unwrap();
    let generation = state.connections.generation;
    let pairing_file = state.pairing_file.clone();
    let connection = state.connections.checkout().map(OwnedRsdConnection);
    (connection, pairing_file, generation)
}

pub fn store_rppairing_rsd_connection(connection: OwnedRsdConnection) -> bool {
    RPPAIRING_STATE
        .lock()
        .unwrap()
        .connections
        .store_if_current(connection.0)
}

fn new_owned_connection(
    connection: CachedRsdConnection,
    generation: u64,
) -> OwnedRsdConnection {
    OwnedRsdConnection(GenerationOwner {
        value: connection,
        generation,
    })
}

pub async fn connect_to_rsd_services<Service: RsdService>() -> Result<Service, IdeviceError> {
    let (cached_connection, pairing_file, generation) = checkout_connection();
    if let Some(mut connection) = cached_connection {
        let result = Service::connect_rsd(&mut connection.adapter, &mut connection.handshake).await;
        match result {
            Ok(service) => {
                info!("using existing connection");
                store_rppairing_rsd_connection(connection);
                return Ok(service);
            }
            Err(IdeviceError::Socket(_)) => {
                // Reconnect below. The failed owned connection is dropped.
            }
            Err(error) => {
                store_rppairing_rsd_connection(connection);
                return Err(error);
            }
        }
    }

    let pairing_file = match pairing_file {
        Some(pairing_file) => pairing_file,
        None => {
            error!("No PairingFile");
            return Err(IdeviceError::UserDeniedPairing);
        }
    };
    let connection = create_rppairing_rsd_connection(pairing_file).await?;
    info!("creating new connection");
    let mut connection = new_owned_connection(connection, generation);
    let result = Service::connect_rsd(&mut connection.adapter, &mut connection.handshake).await;
    store_rppairing_rsd_connection(connection);
    result
}

pub async fn get_or_create_rppairing_rsd_connection(
) -> Result<OwnedRsdConnection, IdeviceError> {
    let (cached_connection, pairing_file, generation) = checkout_connection();
    if let Some(mut connection) = cached_connection {
        if HeartbeatClient::connect_rsd(&mut connection.adapter, &mut connection.handshake)
            .await
            .is_ok()
        {
            error!("using existing connection");
            return Ok(connection);
        }
    }

    let pairing_file = match pairing_file {
        Some(pairing_file) => pairing_file,
        None => {
            error!("No PairingFile");
            return Err(IdeviceError::UserDeniedPairing);
        }
    };
    match create_rppairing_rsd_connection(pairing_file).await {
        Ok(connection) => {
            error!("creating new connection");
            Ok(new_owned_connection(connection, generation))
        }
        Err(error) => {
            error!("create_rppairing_rsd_connection failed: {}", error);
            Err(error)
        }
    }
}

async fn create_rppairing_rsd_connection(
    mut pairing_file: idevice::remote_pairing::RpPairingFile,
) -> Result<CachedRsdConnection, IdeviceError> {
    let socket_addr = SocketAddrV4::from_str("10.7.0.1:49152").unwrap();
    let stream = match tokio::net::TcpStream::connect(socket_addr).await {
        Ok(s) => s,
        Err(e) => {
            return Err(IdeviceError::Socket(e));
        }
    };

    let conn = RpPairingSocket::new(stream);

    let mut rpc = RemotePairingClient::new(conn, &"minimuxer", &mut pairing_file);
    rpc.connect(async |_| "000000".to_string(), 0u8).await?;

    use idevice::remote_pairing::connect_tls_psk_tunnel_native;

    let tunnel_port = rpc.create_tcp_listener().await?;

    let tunnel_addr =
        std::net::SocketAddr::new(std::net::IpAddr::V4(*socket_addr.ip()), tunnel_port);
    let tunnel_stream = tokio::net::TcpStream::connect(tunnel_addr).await?;
    let tunnel = connect_tls_psk_tunnel_native(tunnel_stream, rpc.encryption_key()).await?;
    let client_ip: std::net::IpAddr = tunnel
        .info
        .client_address
        .parse()
        .map_err(|e| IdeviceError::AddrParseError(e))?;
    let server_ip: std::net::IpAddr = tunnel
        .info
        .server_address
        .parse()
        .map_err(|e| IdeviceError::AddrParseError(e))?;
    let mtu = tunnel.info.mtu as usize;
    let rsd_port = tunnel.info.server_rsd_port;

    let raw = tunnel.into_inner();
    let mut adapter = idevice::tcp::adapter::Adapter::new(Box::new(raw), client_ip, server_ip);
    adapter.set_mss(mtu.saturating_sub(60));
    let mut adapter = adapter.to_async_handle();

    let rsd_stream = adapter.connect(rsd_port).await?;
    let handshake = RsdHandshake::new(rsd_stream).await?;

    Ok(CachedRsdConnection { adapter, handshake })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn pairing_file_is_replaced_and_clearable() {
        clear_rppairing_state();
        let first = idevice::remote_pairing::RpPairingFile::generate("first");
        let second = idevice::remote_pairing::RpPairingFile::generate("second");
        let initial_generation = rppairing_generation();

        set_rppairing_file(String::from_utf8(first.to_bytes()).unwrap()).unwrap();
        assert!(has_rppairing_file());
        assert_eq!(
            RPPAIRING_STATE
                .lock()
                .unwrap()
                .pairing_file
                .as_ref()
                .unwrap()
                .identifier(),
            first.identifier()
        );

        set_rppairing_file(String::from_utf8(second.to_bytes()).unwrap()).unwrap();
        assert_eq!(rppairing_generation(), initial_generation + 2);
        assert_eq!(
            RPPAIRING_STATE
                .lock()
                .unwrap()
                .pairing_file
                .as_ref()
                .unwrap()
                .identifier(),
            second.identifier()
        );
        assert!(!has_cached_rsd_connection());

        clear_rppairing_state();
        assert!(!has_rppairing_file());
        assert!(!has_cached_rsd_connection());
    }

    #[test]
    fn clear_completes_with_in_flight_owner_and_stale_connection_is_not_restored() {
        let mut cache = GenerationCache::with_value(7_u8);
        let owner = cache.checkout().expect("connection must be checked out");

        cache.invalidate();

        assert!(!cache.store_if_current(owner));
        assert!(cache.value.is_none());
    }
}
