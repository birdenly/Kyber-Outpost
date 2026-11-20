import 'package:collection/collection.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_fadein/flutter_fadein.dart';
import 'package:kyber_launcher/features/kyber/models/maps.dart';
import 'package:kyber_launcher/features/kyber/models/mode.dart';
import 'package:kyber_launcher/features/kyber/models/modes.dart';
import 'package:kyber_launcher/features/server_browser/models/server_list_state.dart';
import 'package:kyber_launcher/features/server_browser/providers/server_list_cubit.dart';
import 'package:kyber_launcher/features/server_browser/widgets/server_list/entry.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:super_sliver_list/super_sliver_list.dart';

class TableServerList extends StatefulWidget {
  const TableServerList({super.key});

  @override
  State<TableServerList> createState() => _TableServerListState();
}

class _TableServerListState extends State<TableServerList> {
  int? hoverIndex;

  @override
  void initState() {
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return FadeIn(
      curve: Curves.easeOut,
      duration: const Duration(milliseconds: 100),
      child: BlocBuilder<ServerListCubit, ServerListState>(
        builder: (_, state) {
          state as ServerListLoaded;
          final servers = state.servers;

          if (servers.isEmpty) {
            return Center(
              child: Text(
                'No servers found',
                style: FluentTheme.of(context).typography.subtitle?.copyWith(
                  fontFamily: FontFamily.battlefrontUI,
                ),
              ),
            );
          }

          return FadeIn(
            duration: const Duration(milliseconds: 150),
            child: SuperListView.builder(
              itemBuilder: (context, index) {
                if (index == servers.length) {
                  return const SizedBox.shrink();
                }

                final server = servers[index];
                final serverInfo = server.serverInfo;
                final mode =
                    modes
                        .where(
                          (element) =>
                              element.mode == serverInfo.levelSetup.mode,
                        )
                        .firstOrNull ??
                    Mode.customMode();
                final map = mode.maps.isEmpty
                    ? maps.first
                    : maps.firstWhereOrNull(
                            (element) =>
                                element['map'] == serverInfo.levelSetup.map,
                          ) ??
                          maps.first;

                return ServerListEntry(
                  server: server,
                  index: index,
                  isLast: index == servers.length,
                  hoveredIndex: hoverIndex ?? -1,
                  onHover: (value) {
                    setState(() => hoverIndex = value ? index : null);
                  },
                  mode: mode,
                  map: map,
                );
              },
              itemCount: servers.isEmpty ? 0 : servers.length,
            ),
          );
        },
      ),
    );
  }
}
