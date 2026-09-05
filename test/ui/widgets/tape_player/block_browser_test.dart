import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/block_browser.dart';
import 'package:zx_tape_to_wav_x/zx_tape_to_wav_x.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('keeps its content above the bottom system inset', (
    tester,
  ) async {
    const bottomInset = 24.0;
    final blocks = <TapeBlockInfo>[
      TapeBlockInfo(
        index: 0,
        typeName: 'Snapshot',
        title: 'Snapshot bootstrap',
        isHeader: true,
        sampleOffset: 0,
        timeOffset: Duration.zero,
        duration: const Duration(seconds: 1),
      ),
    ];
    var selected = 0;

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: _TestApp(
          bottomInset: bottomInset,
          blocks: blocks,
          onBlockTap: (_) => selected++,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final safeAreaFinder = find.descendant(
      of: find.byType(BlockBrowser),
      matching: find.byType(SafeArea),
    );
    final contentFinder = find
        .descendant(of: safeAreaFinder, matching: find.byType(Column))
        .first;

    expect(safeAreaFinder, findsOneWidget);
    expect(contentFinder, findsOneWidget);

    final safeArea = tester.widget<SafeArea>(safeAreaFinder);
    expect(safeArea.top, isFalse);
    expect(safeArea.bottom, isTrue);

    final browserBottom = tester.getBottomRight(find.byType(BlockBrowser)).dy;
    final contentBottom = tester.getBottomRight(contentFinder).dy;
    expect(browserBottom - contentBottom, bottomInset);
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNotNull);
    await tester.tap(find.text('Snapshot: Snapshot bootstrap'));
    expect(selected, 1);

    await tester.tap(find.byKey(const ValueKey('disable_block_navigation')));
    await tester.pump();
    expect(tester.widget<InkWell>(find.byType(InkWell)).onTap, isNull);
    await tester.tap(find.text('Snapshot: Snapshot bootstrap'));
    expect(selected, 1);
  });
}

class _TestApp extends StatefulWidget {
  const _TestApp({
    required this.bottomInset,
    this.blocks = const [],
    this.onBlockTap,
  });

  final double bottomInset;
  final List<TapeBlockInfo> blocks;
  final ValueChanged<int>? onBlockTap;

  @override
  State<_TestApp> createState() => _TestAppState();
}

class _TestAppState extends State<_TestApp> {
  bool _navigationEnabled = true;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 320.0,
            height: 300.0,
            child: Stack(
              children: [
                MediaQuery(
                  data: MediaQueryData(
                    padding: EdgeInsets.only(bottom: widget.bottomInset),
                  ),
                  child: BlockBrowser(
                    blocks: widget.blocks,
                    currentPosition: Duration.zero,
                    onBlockTap: _navigationEnabled ? widget.onBlockTap : null,
                  ),
                ),
                Positioned(
                  right: 0,
                  child: GestureDetector(
                    key: const ValueKey('disable_block_navigation'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => setState(() {
                      _navigationEnabled = false;
                    }),
                    child: const SizedBox(width: 24, height: 24),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
