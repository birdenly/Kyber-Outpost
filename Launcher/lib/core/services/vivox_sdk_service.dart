import 'package:flutter/foundation.dart';

/// Kept for existing callers; cloud voice is disabled in the LAN build.
class VivoxService with ChangeNotifier {
  Future<VivoxService> getInstance() async => this;
}
