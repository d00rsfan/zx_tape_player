import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zx_tape_player/ui/widgets/tape_player/block_browser.dart';

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

    await tester.pumpWidget(
      EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        path: 'assets/translations',
        fallbackLocale: const Locale('en', 'US'),
        child: const _TestApp(bottomInset: bottomInset),
      ),
    );
    await tester.pumpAndSettle();

    final safeAreaFinder = find.descendant(
      of: find.byType(BlockBrowser),
      matching: find.byType(SafeArea),
    );
    final contentFinder = find.descendant(
      of: safeAreaFinder,
      matching: find.byType(Column),
    );

    expect(safeAreaFinder, findsOneWidget);
    expect(contentFinder, findsOneWidget);

    final safeArea = tester.widget<SafeArea>(safeAreaFinder);
    expect(safeArea.top, isFalse);
    expect(safeArea.bottom, isTrue);

    final browserBottom = tester.getBottomRight(find.byType(BlockBrowser)).dy;
    final contentBottom = tester.getBottomRight(contentFinder).dy;
    expect(browserBottom - contentBottom, bottomInset);
  });
}

class _TestApp extends StatelessWidget {
  const _TestApp({required this.bottomInset});

  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      localizationsDelegates: context.localizationDelegates,
      supportedLocales: context.supportedLocales,
      locale: context.locale,
      home: Scaffold(
        body: Center(
          child: MediaQuery(
            data: MediaQueryData(padding: EdgeInsets.only(bottom: bottomInset)),
            child: SizedBox(
              width: 320.0,
              height: 300.0,
              child: BlockBrowser(
                blocks: const [],
                currentPosition: Duration.zero,
                onBlockTap: (_) {},
              ),
            ),
          ),
        ),
      ),
    );
  }
}
