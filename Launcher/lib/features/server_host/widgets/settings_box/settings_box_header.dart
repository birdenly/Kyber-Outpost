// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:form_builder_validators/form_builder_validators.dart';
import 'package:grpc/grpc.dart';
import 'package:kyber/gen/Proto/kyber_common.pb.dart';
import 'package:kyber/kyber.dart' hide ServerMod;
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/instance_manager.dart';
import 'package:kyber_launcher/core/services/notification_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_discovery_service.dart';
import 'package:kyber_launcher/features/lan/services/lan_mod_server_service.dart';
import 'package:kyber_launcher/features/map_rotation/providers/map_rotation_cubit.dart';
import 'package:kyber_launcher/features/maxima/extensions/server_mod.dart';
import 'package:kyber_launcher/features/maxima/helper/maxima_helper.dart';
import 'package:kyber_launcher/features/maxima/models/maxima_game_instance.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/features/mod_collections/extensions/mod_collection_extension.dart';
import 'package:kyber_launcher/features/mods/services/level_declaration_service.dart';
import 'package:kyber_launcher/features/server_host/providers/host_collection_cubit.dart';
import 'package:kyber_launcher/features/server_host/widgets/settings_box/server_settings_box.dart';
import 'package:kyber_launcher/features/server_moderation/providers/moderation_cubit.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/ui.dart';
import 'package:logging/logging.dart';

class SettingsBoxHeader extends StatelessWidget {
  const SettingsBoxHeader({
    required this.onPageChanged,
    required this.selectedPage,
    super.key,
  });

  final void Function(int page) onPageChanged;
  final int selectedPage;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(10).copyWith(left: 10, top: 20, right: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BlocBuilder<ModerationCubit, ModerationServerState>(
            builder: (context, state) {
              return FractionallySizedBox(
                widthFactor: 0.8,
                child: KyberFormInputField(
                  name: 'serverName',
                  initialValue: state.selected ? state.server?.name : null,
                  validator: FormBuilderValidators.compose([
                    FormBuilderValidators.required(),
                    FormBuilderValidators.minLength(3),
                    FormBuilderValidators.maxLength(25),
                  ]),
                  placeholder: 'Server Name',
                ),
              );
            },
          ),
          const SizedBox(
            height: 10,
          ),

          //FractionallySizedBox(
          //  widthFactor: 0.8,
          //  child: KyberFormInputField(
          //    name: "tags",
          //    placeholder: Localization.current.hostServerTagsPlaceholder,
          //  ),
          //),
          const SizedBox(
            height: 30,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              BlocBuilder<ModerationCubit, ModerationServerState>(
                builder: (context, state) {
                  return Row(
                    children: [
                      KyberButton(
                        text: state.selected ? 'UPDATE SERVER' : 'START SERVER',
                        onPressed: () async {
                          final form = hostingForm.currentState!;
                          if (!form.saveAndValidate()) {
                            final firstKey = form.errors.entries.first;
                            NotificationService.showNotification(
                              title: firstKey.key,
                              message: firstKey.value,
                              severity: InfoBarSeverity.error,
                            );
                            return;
                          }

                          if (state.selected) {
                            NotificationService.showNotification(
                              message: 'Server updated',
                            );
                            return;
                          }

                          final mapRotation = context
                              .read<MapRotationCubit>()
                              .state
                              .maps
                              .map(
                                (e) {
                                  return LevelSetup(
                                    map: e.map,
                                    mode: e.mode,
                                    mapName: sl
                                        .get<LevelDeclarationService>()
                                        .getMapByMode(
                                          map: e.map,
                                          mode: e.mode,
                                          collection: context
                                              .read<HostCollectionCubit>()
                                              .state
                                              .selectedModCollection,
                                        )
                                        ?.name,
                                    modeName: sl
                                        .get<LevelDeclarationService>()
                                        .getModeName(
                                          mode: e.mode,
                                          collection: context
                                              .read<HostCollectionCubit>()
                                              .state
                                              .selectedModCollection,
                                        ),
                                  );
                                },
                              )
                              .toList();
                          final collection = context
                              .read<HostCollectionCubit>()
                              .state
                              .selectedModCollection;

                          if (mapRotation.isEmpty) {
                            NotificationService.error(
                              message:
                                  'You need to add at least one map to the map rotation',
                            );
                            return;
                          }

                          try {
                            final startRequest = StartServerRequest(
                              name: form.value['serverName'] as String,
                              description: form.value['description'] as String?,
                              password: form.value['password'] as String?,
                              maxPlayers: form.value['maxPlayers'] as int?,
                              mapRotation: mapRotation,
                            );

                            final orderedFrostyMods = collection
                                .getLocalMods(
                                  onlyGameplay: true,
                                  expandCollections: true,
                                )
                                .whereType<FrostyMod>()
                                .where((e) => !e.isCollection)
                                .toList();
                            final orderedServerMods = orderedFrostyMods
                                .map(ServerMod().fromFrostyMod)
                                .toList();
                            final hostCreator =
                                context
                                    .read<MaximaCubit>()
                                    .state
                                    .servicePlayer
                                    ?.displayName ??
                                'OutpostHost';
                            final serverId =
                                'lan_host_${startRequest.name}_${InstanceManager.gamePort}';

                            final lanModServer = sl.get<LanModServerService>();
                            await lanModServer.configureHostedServer(
                              serverId: serverId,
                              serverName: startRequest.name,
                              description: startRequest.description,
                              creator: hostCreator,
                              requiresPassword:
                                  startRequest.password.isNotEmpty,
                              maxPlayers: startRequest.maxPlayers > 0
                                  ? startRequest.maxPlayers
                                  : 40,
                              levelSetup: mapRotation.first,
                              orderedMods: orderedFrostyMods,
                              gamePort: InstanceManager.gamePort,
                            );

                            await sl
                                .get<LanDiscoveryService>()
                                .startBroadcasting(
                                  serverId: serverId,
                                  name: startRequest.name,
                                  description: startRequest.description,
                                  creator: hostCreator,
                                  requiresPassword:
                                      startRequest.password.isNotEmpty,
                                  maxPlayers: startRequest.maxPlayers > 0
                                      ? startRequest.maxPlayers
                                      : 40,
                                  levelSetup: mapRotation.first,
                                  mods: orderedServerMods,
                                  gamePort: InstanceManager.gamePort,
                                  httpPort: lanModServer.port,
                                );

                            final initialCommands = <String>[];

                            if (form.value['friendlyFire'] as bool? ?? false) {
                              initialCommands.add(
                                'SyncedGame.EnableFriendlyFire 1',
                              );
                            }

                            final healthRegen =
                                form.value['healthRegeneration'] as bool? ??
                                true;
                            if (!healthRegen) {
                              initialCommands.add(
                                'SyncedGame.DisableRegenerateHealth 1',
                              );
                            }

                            if (sl.isRegistered<MaximaGameInstance>()) {
                              if (initialCommands.isNotEmpty) {
                                NotificationService.showNotification(
                                  message:
                                      'Friendly Fire and Health Regeneration can only be set when no game is running',
                                  severity: InfoBarSeverity.error,
                                );
                              }

                              final client = sl
                                  .get<MaximaGameInstance>()
                                  .clientService;
                              final state = await client.commonClient.getInfo(
                                Empty(),
                              );
                              if (state.hasClient() || state.hasServer()) {
                                Logger.root.info(
                                  'Client or server is already running',
                                );
                                return;
                              }

                              await client.serverClient.startServer(
                                startRequest,
                              );
                            } else {
                              await MaximaHelper.requestGameLaunch(
                                context,
                                initializeRequest: InitializeRequest(
                                  startServer: startRequest,
                                  startupCommands: initialCommands,
                                ),
                                modCollection: collection,
                              );
                            }
                          } on GrpcError catch (e) {
                            Logger.root.severe(
                              'Failed to start server: ${e.message}',
                            );
                            NotificationService.error(
                              message: 'Failed to start server: ${e.message}',
                            );
                          } catch (e, stack) {
                            Logger.root.severe(
                              'Unexpected error while starting server',
                              e,
                              stack,
                            );
                            NotificationService.error(
                              message:
                                  'An unexpected error occurred while starting the server',
                            );
                          }
                        },
                      ),
                    ],
                  );
                },
              ),
              SizedBox(
                height: 35,
                width: 220,
                child: KyberTabBar(
                  tabs: [
                    Text('Settings'.toUpperCase()),
                    Text('Info'.toUpperCase()),
                  ],
                  onChanged: onPageChanged,
                  selectedIndex: selectedPage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
