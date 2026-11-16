import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:kyber_collection/kyber_collection.dart';
import 'package:kyber_launcher/core/services/app_settings.dart';
import 'package:kyber_launcher/features/maxima/providers/maxima_cubit.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';
import 'package:kyber_launcher/main.dart';
import 'package:kyber_launcher/shared/ui/utils/hive_listener.dart';
import 'package:path/path.dart';

class KyberBackground extends StatelessWidget {
  const KyberBackground({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        HiveListener(
          box: box,
          keys: const [
            'removeBackground',
            'backgroundImage',
            'customBackground',
          ],
          builder: (_) {
            ImageProvider? imageProvider;
            if (Preferences.customization.customBackground) {
              imageProvider = FileImage(
                File(
                  join(FileHelper.getLauncherDirectory().path, 'background'),
                ),
              );
            } else if (Preferences.customization.backgroundImage != null &&
                context.read<MaximaCubit>().state.isEntitled(
                  .admin,
                )) {
              final imagePath = Preferences.customization.backgroundImage!;
              if (imagePath.startsWith('http')) {
                imageProvider = CachedNetworkImageProvider(imagePath);
              } else {
                imageProvider = AssetImage(imagePath);
              }
            }

            if (Preferences.admin.removeBackground) {
              return Container(color: Colors.black);
            }

            if (imageProvider != null) {
              return Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: 0.2),
                      BlendMode.darken,
                    ),
                  ),
                ),
              );
            }

            return Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF04070B),
                    Color(0xFF0A1420),
                    Color(0xFF132538),
                    Color(0xFF080F18),
                  ],
                  stops: [0.0, 0.42, 0.76, 1.0],
                ),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.55, 0.15),
                    radius: 0.95,
                    colors: [
                      Color(0x40213D58),
                      Color(0x1813263A),
                      Color(0x0004070B),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            );
          },
        ),
        Directionality(
          textDirection: TextDirection.ltr,
          child: material.Material(
            type: .transparency,
            textStyle: FluentTheme.of(context).typography.body?.copyWith(
              fontFamily: FontFamily.battlefrontUI,
            ),
            child: NavigationPaneTheme(
              data: const NavigationPaneThemeData(
                backgroundColor: Colors.transparent,
              ),
              child: child,
            ),
          ),
        ),
      ],
    );
  }
}
