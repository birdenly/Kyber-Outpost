import 'dart:async';

import 'package:kyber/kyber.dart' show ClientGRPCService;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/features/mods/constants/categories.dart';

class MaximaGameInstance {
  MaximaGameInstance({
    required this.pid,
    required this.isDedicated,
    required this.clientService,
    this.mods = const [],
  }) {
    _eventStreamController = StreamController<String>.broadcast();
  }

  int pid;
  bool isDedicated;
  ClientGRPCService clientService;
  List<FrostyMod> mods;

  late StreamController<String> _eventStreamController;

  void addEvent(String event) {
    _eventStreamController.add(event);
  }

  Future<void> closeStream() async {
    await _eventStreamController.close();
  }

  Stream<String> get eventStream => _eventStreamController.stream;

  List<FrostyMod> get gameplayMods => mods
      .where(
        (m) => kRequiredCategories.contains(m.details.category.toLowerCase()),
      )
      .toList(growable: false);

  MaximaGameInstance copyWith({
    int? pid,
    bool? isDedicated,
    ClientGRPCService? clientService,
    List<FrostyMod>? mods,
  }) {
    return MaximaGameInstance(
      pid: pid ?? this.pid,
      isDedicated: isDedicated ?? this.isDedicated,
      clientService: clientService ?? this.clientService,
      mods: mods ?? this.mods,
    );
  }
}
