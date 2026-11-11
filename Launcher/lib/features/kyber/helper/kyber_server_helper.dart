// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:grpc/grpc.dart' hide Server;
import 'package:kyber/kyber.dart' hide ServerMod;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/routing/app_router.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_api_status_cubit.dart';
import 'package:kyber_launcher/features/kyber/providers/kyber_proxy_cubit.dart';
import 'package:kyber_launcher/features/maxima/dialogs/maxima_start_game_dialog.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/mod_collections/extensions/mod_collection_extension.dart';
import 'package:kyber_launcher/features/mods/extensions/frosty_collection_extension.dart';
import 'package:kyber_launcher/features/mods/services/mod_service.dart';
import 'package:kyber_launcher/features/session/providers/session_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';
import 'package:logging/logging.dart';

class KyberServerHelper {
  static final _logger = Logger('kyber_server_helper');

  static Future<void> joinServer(
    Server server, {
    ModCollectionMetaData? selectedCollection,
    bool? spectator,
    String? password,
    bool queueIfFull = false,
  }) async {
    final localMods = sl.get<ModService>().mods;
    final mods = server.mods.map((e) {
      final matches = localMods
          .where(
            (element) => element.toKyberString() == '${e.name} (${e.version})',
          )
          .toList();

      return matches.firstWhereOrNull(
            (m) => !m.isCollection || !m.isCorrupted(),
          ) ??
          matches.first;
    });
    final collectionMods = <CollectionMod>[];
    for (final mod in mods) {
      if (mod.isCollection) {
        final cMods = mod.getMods()!.map(
          (e) => localMods
              .firstWhereOrNull((x) => x.filename == e)
              ?.toCollectionMod(),
        );
        if (cMods.contains(null)) {
          throw Exception(
            '"${mod.details.name}" is corrupted. Please reinstall it',
          );
        }

        collectionMods.addAll(cMods.whereType<CollectionMod>());
      } else {
        collectionMods.add(mod.toCollectionMod());
      }
    }

    final tmpCollection = ModCollectionMetaData(
      title: server.name,
      mods: [
        if ((selectedCollection != null &&
                !selectedCollection.containsGameplayMods()) ||
            selectedCollection == null)
          ...collectionMods,
        if (selectedCollection != null) ...selectedCollection.mods,
      ],
      localId: server.id,
    );

    var serverIp = server.ip;
    final currentIp = await KyberNetworkHelper.getCurrentIpAddress();
    if (serverIp.isEmpty || serverIp == currentIp) {
      serverIp = '127.0.0.1';
    }

    final targetPort = server.port > 0 ? server.port : 25200;
    _logger.info(
      'Joining LAN server directly at $serverIp:$targetPort '
      'with ${tmpCollection.mods.length} mod(s) in exact Host load order',
    );

    try {
      final joinRequest = JoinServerRequest(
        id: server.id,
        ip: serverIp,
        port: targetPort,
        type: .DIRECT,
        spectate: spectator ?? false,
        joinToken: password ?? '',
      );

      if (!sl.isRegistered<MaximaGameInstance>()) {
        await showKyberDialog(
          context: navigatorKey.currentContext!,
          builder: (_) => MaximaStartGameDialog(
            mods: tmpCollection.getLocalMods().whereType<FrostyMod>().toList(),
            initializeRequest: InitializeRequest(
              joinServer: joinRequest,
              modData: tmpCollection.getInterfaceData(),
            ),
          ),
        );
      } else {
        final instance = sl.get<MaximaGameInstance>();
        await instance.clientService.client.joinServer(
          joinRequest,
        );
      }
    } on GrpcError catch (e) {
      _logger.severe('Failed to join server: ${e.message}', e);
      NotificationService.error(
        message: 'Failed to join server: ${e.message}',
      );
    } catch (e) {
      _logger.severe('Failed to join server: $e', e);
      NotificationService.error(
        message: 'Failed to join server: $e',
      );
    }
  }

  static Future<void> _joinQueueForServer(
    Server server, {
    ModCollectionMetaData? selectedCollection,
    bool? spectator,
    String? password,
  }) async {
    final sessionCubit = navigatorKey.currentContext?.read<SessionCubit>();
    if (sessionCubit == null) {
      return;
    }

    try {
      await sessionCubit.joinQueue(
        server,
        password: password ?? '',
        spectator: spectator ?? false,
        selectedCollection: selectedCollection,
      );

      NotificationService.info(
        message: 'Server is full. You joined the queue.',
      );
    } on GrpcError catch (e) {
      if (e.code == StatusCode.failedPrecondition &&
          (e.message?.contains('not full') ?? false)) {
        NotificationService.info(
          message: 'Joining server...',
        );
        await joinServer(
          server,
          selectedCollection: selectedCollection,
          spectator: spectator,
          password: password,
        );
        return;
      }

      _logger.severe('Failed to join server queue: ${e.message}', e);
      NotificationService.error(
        message: 'Failed to join server queue: ${e.message}',
      );
    }
  }
}
