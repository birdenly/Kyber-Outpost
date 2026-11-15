import 'dart:io';

/// Local network interfaces and ports; no public IP lookup is performed.
class KyberNetworkHelper {
  KyberNetworkHelper._();

  /// Returns a local IPv4 address, or loopback when no interface is available.
  static Future<String> getCurrentIpAddress() async {
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
    );
    return interfaces
            .expand((interface) => interface.addresses)
            .firstOrNull
            ?.address ??
        InternetAddress.loopbackIPv4.address;
  }

  /// Checks all local interfaces so VPN and multi-adapter hosts are supported.
  static Future<bool> isLocalIpAddress(String address) async {
    final parsed = InternetAddress.tryParse(address);
    if (parsed?.isLoopback ?? false) {
      return true;
    }
    final interfaces = await NetworkInterface.list(includeLoopback: true);
    return interfaces.any(
      (interface) =>
          interface.addresses.any((local) => local.address == address),
    );
  }

  /// Finds a free TCP port for a local control service.
  static Future<int> findAvailablePort({int i = 0}) async {
    ServerSocket? server;
    try {
      server = await ServerSocket.bind('0.0.0.0', 0);
      final port = server.port;

      if (i > 10) {
        throw Exception('No available port found');
      }

      if (port == 0 || port == 443 || port == 80) {
        return await findAvailablePort(i: i + 1);
      }

      return port;
    } finally {
      await server?.close();
    }
  }
}
