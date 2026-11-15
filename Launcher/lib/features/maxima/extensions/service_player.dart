import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/gen/assets.gen.dart';
import 'package:kyber_launcher/gen/rust/api/outpost.dart';

extension on ServicePlayer {
  Image avatarImage() {
    if (avatar != null) {
      return Image.network(avatar!.medium.path);
    }

    return Assets.images.usericonTmp.image();
  }
}
