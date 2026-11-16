// Modified for Kyber Outpost (LAN Edition) - 2026-11-10.
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_launcher/features/mod_browser/providers/mod_browser_cubit.dart';
import 'package:kyber_launcher/features/mod_browser/providers/mod_search_cubit.dart';
import 'package:kyber_launcher/features/mod_browser/widgets/nmb_mod_tile.dart';
import 'package:kyber_launcher/features/nexusmods/dialogs/nexusmods_login.dart';
import 'package:kyber_launcher/features/nexusmods/services/nexusmods_service.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/injection_container.dart';
import 'package:kyber_launcher/shared/ui/buttons/button.dart';
import 'package:kyber_launcher/shared/ui/dialog/kyber_dialog.dart';

class CategorizedModList extends StatefulWidget {
  const CategorizedModList({super.key});

  @override
  State<CategorizedModList> createState() => _CategorizedModListState();
}

class _CategorizedModListState extends State<CategorizedModList> {
  Widget _buildErrorView(BuildContext context, String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      spacing: 20,
      children: [
        Text(
          message,
          style: const TextStyle(
            fontFamily: FontFamily.battlefrontUI,
            fontSize: 17,
          ),
          textAlign: TextAlign.center,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            KyberButton(
              text: 'RETRY',
              onPressed: () {
                context.read<ModBrowserCubit>().loadPage(force: true);
              },
            ),
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: sl.isReady<NexusModsService>(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _buildErrorView(
            context,
            ModBrowserCubit.kOfflineErrorMessage,
          );
        }

        if (!snapshot.hasData) {
          return const Center(child: ProgressRing());
        }

        return BlocBuilder<ModBrowserCubit, ModBrowserState>(
          builder: (context, state) {
            if (state is ModBrowserError) {
              return _buildErrorView(context, state.error);
            }

            if (sl.get<NexusModsService>().apiToken == null) {
              if (state is ModBrowserLoading) {
                return const Center(child: ProgressRing());
              }

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                spacing: 20,
                children: [
                  const Text('Please sign in to Nexus Mods to view mods'),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      KyberButton(
                        text: 'LOGIN',
                        onPressed: () async {
                          await showKyberDialog(
                            context: context,
                            builder: (_) => const NexusmodsLogin(),
                            routeSettings: const RouteSettings(
                              name: 'nexusmods_login',
                            ),
                          );
                          if (context.mounted) {
                            await context.read<ModBrowserCubit>().loadPage();
                            setState(() {});
                          }
                        },
                      ),
                    ],
                  ),
                ],
              );
            }

            return BlocBuilder<ModSearchCubit, SearchState>(
              builder: (context, searchState) {
                if (searchState is SearchLoading) {
                  return const Center(child: ProgressRing());
                }

                if (searchState is SearchLoaded) {
                  if (searchState.results.isEmpty) {
                    return Center(
                      child: Text(
                        'No mods found'.toUpperCase(),
                        style: const TextStyle(
                          fontFamily: FontFamily.battlefrontUI,
                          fontSize: 17,
                        ),
                      ),
                    );
                  }

                  return GridView.builder(
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                          maxCrossAxisExtent: 375,
                          childAspectRatio: 16 / 9,
                          crossAxisSpacing: 15,
                          mainAxisSpacing: 15,
                        ),
                    padding: const .symmetric(
                      vertical: 20,
                      horizontal: 20,
                    ),
                    itemBuilder: (context, index) {
                      final mod = searchState.results[index];
                      return NMBModTile(
                        key: Key(mod.id),
                        mod: .new(
                          name: mod.name,
                          downloads: mod.downloads,
                          id: mod.id,
                          modId: mod.modId,
                          summary: mod.summary,
                          uid: mod.uid,
                          uploader: .new(
                            name: mod.uploader.name,
                            avatar: mod.uploader.avatar,
                          ),
                          author: mod.author,
                          fileSize: mod.fileSize,
                          pictureUrl: mod.pictureUrl,
                          thumbnailUrl: mod.thumbnailUrl,
                        ),
                      );
                    },
                    itemCount: searchState.results.length,
                  );
                }

                if (searchState is SearchError) {
                  return _buildErrorView(context, searchState.error);
                }

                if (state is ModBrowserLoading || state is ModBrowserInitial) {
                  return const Center(child: ProgressRing());
                }

                state as ModBrowserLoaded;

                return GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 375,
                    childAspectRatio: 16 / 9,
                    crossAxisSpacing: 15,
                    mainAxisSpacing: 15,
                  ),
                  padding: const EdgeInsets.symmetric(
                    vertical: 20,
                    horizontal: 20,
                  ),
                  itemBuilder: (context, index) {
                    final mod = state.mods[index];
                    return NMBModTile(
                      key: Key(mod.id),
                      mod: mod,
                    );
                  },
                  itemCount: state.mods.length,
                );
              },
            );
          },
        );
      },
    );
  }
}
