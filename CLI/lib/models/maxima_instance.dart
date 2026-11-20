import 'package:kyber_collection/kyber_collection.dart';

const kRequiredCategories = ['gameplay', 'maps', 'map'];

class MaximaGameInstance {
  MaximaGameInstance({
    required this.pid,
    this.mods = const [],
  });

  int pid;
  List<FrostyMod> mods;

  List<FrostyMod> get gameplayMods => mods
      .where(
        (m) => kRequiredCategories.contains(m.details.category.toLowerCase()),
      )
      .toList(growable: false);
}
