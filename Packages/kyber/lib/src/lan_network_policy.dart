import 'dart:io';

/// HTTP access for LAN/VPN services and the existing mod browser. Other remote
/// hosts are rejected before DNS resolution, including on HTTP redirects.
class LanNetworkPolicy extends HttpOverrides {
  static const _modDomains = [
    'nexusmods.com',
    'nexus-cdn.com',
    'nexusmodsusercontent.com',
  ];
  static const _modServices = [
    'mod-service.prod.kyber.gg',
    'mod-bridge.reax.at',
  ];

  /// Applies the LAN and mod-host policy to HTTP clients in this isolate.
  static void install() {
    HttpOverrides.global = LanNetworkPolicy();
  }

  /// Permits numeric LAN/VPN addresses and the mod browser services.
  static bool allowsHost(String hostname) {
    final host = hostname.toLowerCase();
    if (host == 'localhost' || _modServices.contains(host)) {
      return true;
    }
    if (_modDomains.any(
      (domain) => host == domain || host.endsWith('.$domain'),
    )) {
      return true;
    }
    final address = InternetAddress.tryParse(host);
    if (address == null) {
      return false;
    }
    if (address.isLoopback || address.isLinkLocal) {
      return true;
    }
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv6) {
      return (bytes[0] & 0xfe) == 0xfc; // IPv6 unique local addresses.
    }
    return bytes[0] == 10 ||
        bytes[0] == 25 || // Hamachi: 25.0.0.0/8.
        bytes[0] == 26 || // Radmin VPN: 26.0.0.0/8.
        (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31) ||
        (bytes[0] == 192 && bytes[1] == 168) ||
        (bytes[0] == 100 && bytes[1] >= 64 && bytes[1] <= 127);
  }

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    // A proxy must not forward local requests to an Internet service.
    client.findProxy = (_) => 'DIRECT';
    client.connectionFactory = (uri, proxyHost, proxyPort) async {
      if (!allowsHost(uri.host)) {
        throw SocketException('Internet access is disabled for ${uri.host}');
      }
      return Socket.startConnect(uri.host, uri.port);
    };
    return client;
  }
}
