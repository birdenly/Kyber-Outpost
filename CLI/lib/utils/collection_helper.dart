import 'dart:io';

import 'package:kyber_collection/kyber_collection.dart';
import 'package:mason_logger/mason_logger.dart';

class CollectionHelper {
  final _logger = Logger();

  List<String> getModsList(
    ModCollectionMetaData metaData, {
    bool listFrostyCollectionMods = true,
  }) {
    final paths = List<String>.empty(growable: true);
    for (final mod in metaData.mods) {
      if (!mod.isCollection) {
        paths.add(mod.filename!);
      } else {
        if (listFrostyCollectionMods) {
          for (final collectionMod in mod.mods!) {
            paths.add(collectionMod);
          }
        } else {
          paths.add(mod.filename!);
        }
      }
    }

    return paths;
  }

  String getModsDirectory() {
    return FileHelper.getCollectionDirectory().path;
  }

  Future<void> useCollection(File collectionFile) async {
    if (!collectionFile.existsSync()) {
      throw Exception('Collection file not found');
    }

    final metaData = await ModCollection.readCollection(collectionFile);
    _logger.info(
      'Loading Mod Collection "${metaData.title}" with ${metaData.mods.length} mods',
    );

    final hasModData = await ModCollection.hasFileData(collectionFile);
    if (!hasModData) {
      throw Exception('Mod collection does not contain embedded mod files');
    }

    final started = DateTime.now();
    _logger.info('Extracting Collection');
    await ModCollection.extractCollection(collectionFile);
    _logger.info(
      'Extracting done. (Took ${DateTime.now().millisecondsSinceEpoch - started.millisecondsSinceEpoch}ms)',
    );
  }
}
