import 'package:fluent_ui/fluent_ui.dart';
import 'package:kyber_launcher/core/config/colors.dart';
import 'package:kyber_launcher/gen/fonts.gen.dart';

class TitleBar extends StatelessWidget {
  const TitleBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Image.asset(
            'assets/logos/outpost_icon.png',
            height: 20,
            fit: BoxFit.contain,
          ),
          const SizedBox(width: 8),
          const Text(
            'KYBER OUTPOST',
            style: TextStyle(
              fontFamily: FontFamily.battlefrontUI,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.4,
              color: kWhiteColor,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: kActiveColor),
            ),
            child: Text(
              'LAN EDITION',
              style: TextStyle(
                fontFamily: FontFamily.battlefrontUI,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: kActiveColor,
              ),
            ),
          ),
          const Spacer(),
        ],
      ),
    );
  }
}
