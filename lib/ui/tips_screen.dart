import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:zx_tape_player/utils/extensions.dart';

class TipsScreen extends StatelessWidget {
  const TipsScreen({super.key});
  static const routeName = '/tips';

  @override
  Widget build(BuildContext context) {
    final tips = <_Tip>[
      _Tip(
        icon: Icons.view_carousel_rounded,
        titleKey: 'tip_carousel_title',
        bodyKey: 'tip_carousel_body',
      ),
      _Tip(
        icon: Icons.download_rounded,
        titleKey: 'tip_download_title',
        bodyKey: 'tip_download_body',
      ),
      _Tip(
        icon: Icons.list_rounded,
        titleKey: 'tip_blocks_title',
        bodyKey: 'tip_blocks_body',
      ),
      _Tip(
        icon: Icons.skip_next_rounded,
        titleKey: 'tip_block_transport_title',
        bodyKey: 'tip_block_transport_body',
      ),
      _Tip(
        icon: Icons.stop_rounded,
        titleKey: 'tip_stop_title',
        bodyKey: 'tip_stop_body',
      ),
      _Tip(
        icon: Icons.speed_rounded,
        titleKey: 'tip_speed_title',
        bodyKey: 'tip_speed_body',
      ),
    ];

    return Scaffold(
      backgroundColor: HexColor('#172434'),
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_outlined,
            color: Colors.white,
            size: 16,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          tr('tips_title'),
          style: const TextStyle(color: Colors.white, letterSpacing: 0.1),
        ),
        titleSpacing: 0.0,
        toolbarHeight: 60.0,
        backgroundColor: HexColor('#28384C'),
      ),
      body: SafeArea(
        top: false,
        child: ListView.separated(
          padding: const EdgeInsets.fromLTRB(16.0, 16.0, 16.0, 24.0),
          itemCount: tips.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12.0),
          itemBuilder: (context, index) => _TipCard(tip: tips[index]),
        ),
      ),
    );
  }
}

class _Tip {
  const _Tip({
    required this.icon,
    required this.titleKey,
    required this.bodyKey,
  });

  final IconData icon;
  final String titleKey;
  final String bodyKey;
}

class _TipCard extends StatelessWidget {
  const _TipCard({required this.tip});

  final _Tip tip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: HexColor('#3B4E63'),
        borderRadius: BorderRadius.circular(8.0),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40.0,
            height: 40.0,
            decoration: BoxDecoration(
              color: HexColor('#28384C'),
              borderRadius: BorderRadius.circular(8.0),
            ),
            alignment: Alignment.center,
            child: Icon(tip.icon, color: Colors.white, size: 22.0),
          ),
          const SizedBox(width: 14.0),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr(tip.titleKey),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14.0,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.1,
                  ),
                ),
                const SizedBox(height: 6.0),
                Text(
                  tr(tip.bodyKey),
                  style: TextStyle(
                    color: HexColor('#B1B8C1'),
                    fontSize: 13.0,
                    letterSpacing: 0.2,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
