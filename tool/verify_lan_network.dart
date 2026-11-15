import 'dart:convert';
import 'dart:io';

import '../Packages/kyber/lib/src/lan_network_policy.dart';
import '../Packages/kyber/lib/src/network_helper.dart';

void check(bool condition, String message) {
  if (!condition) throw StateError(message);
}

Future<void> expectBlocked(HttpClient client, Uri uri) async {
  try {
    final request = await client.getUrl(uri);
    final response = await request.close();
    await response.drain<void>();
  } on SocketException catch (error) {
    check(error.message.contains('Internet access is disabled'), '$error');
    return;
  }
  throw StateError('Expected to block $uri');
}

Future<void> main() async {
  for (final host in [
    'localhost',
    '127.0.0.1',
    '::1',
    '10.0.0.5',
    '192.168.1.7',
    '172.16.0.1',
    '172.31.255.255',
    '100.64.0.1',
    '25.0.0.0',
    '25.255.255.255',
    '26.0.0.0',
    '26.255.255.255',
    '169.254.1.2',
    'fd00::1',
    'api.nexusmods.com',
    'staticdelivery.nexusmods.com',
    'mod-service.prod.kyber.gg',
  ]) {
    check(LanNetworkPolicy.allowsHost(host), 'Blocked LAN/mod host: $host');
  }
  for (final host in [
    'accounts.ea.com',
    'gateway.ea.com',
    'api-rpc.prod.kyber.gg',
    's3.kyber.gg',
    'checkip.amazonaws.com',
    '1.1.1.1',
    '24.255.255.255',
    '27.0.0.0',
    '172.15.0.1',
    '172.32.0.1',
    '100.128.0.1',
    '2001:4860:4860::8888',
    'nexusmods.com.example.invalid',
    'fakenexusmods.com',
  ]) {
    check(
      !LanNetworkPolicy.allowsHost(host),
      'Allowed non-mod Internet host: $host',
    );
  }

  LanNetworkPolicy.install();
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  var requests = 0;
  server.listen((request) async {
    requests++;
    if (request.uri.path == '/redirect') {
      request.response.statusCode = HttpStatus.found;
      request.response.headers.set(
        HttpHeaders.locationHeader,
        'http://accounts.ea.com/',
      );
    } else {
      request.response.write('LAN works');
    }
    await request.response.close();
  });
  final client = HttpClient();
  try {
    final localUri = Uri.parse('http://127.0.0.1:${server.port}');
    final request = await client.getUrl(localUri);
    final response = await request.close();
    check(
      await utf8.decoder.bind(response).join() == 'LAN works',
      'Local HTTP failed',
    );
    await expectBlocked(client, Uri.parse('http://accounts.ea.com/'));
    await expectBlocked(client, Uri.parse('https://checkip.amazonaws.com/'));
    await expectBlocked(client, localUri.resolve('/redirect'));
    check(requests == 2, 'Unexpected requests reached the local server');
    check(
      await KyberNetworkHelper.isLocalIpAddress('127.0.0.1'),
      'Loopback not detected',
    );
    final localIp = await KyberNetworkHelper.getCurrentIpAddress();
    check(
      await KyberNetworkHelper.isLocalIpAddress(localIp),
      'Selected a non-local IP',
    );
    stdout.writeln(
      'PASS: LAN/VPN address ranges, LAN HTTP, local interfaces, '
      'Internet rejection and redirect rejection.',
    );
  } finally {
    client.close(force: true);
    await server.close(force: true);
  }
}
