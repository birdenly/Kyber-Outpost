import 'package:kyber_launcher/features/lightswitch/models/status.dart';

class KyberStatusHelper {
  static Future<LightswitchStatus> checkKyberStatus() async {
    return LightswitchStatus.defaultStatus();
  }
}

class KyberStatus {
  final KyberStatusEnum status;
  final String? message;

  KyberStatus({required this.status, this.message});
}

enum KyberStatusEnum {
  up,
  down,
  warning,
}
