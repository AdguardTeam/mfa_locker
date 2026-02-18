import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mfa_demo/features/locker/views/storage/entry_reveal_screen.dart';

Widget _buildScreen({String entryName = 'Test Entry', String entryValue = 'secret123'}) => MaterialApp(
  home: EntryRevealScreen(
    entryName: entryName,
    entryValue: entryValue,
  ),
);

Future<void> _pumpEntryRevealScreen(
  WidgetTester tester, {
  String entryName = 'Test Entry',
  String entryValue = 'secret123',
}) async {
  await tester.pumpWidget(_buildScreen(entryName: entryName, entryValue: entryValue));
  // First pump fires initState postFrameCallback.
  await tester.pump();
  // Second pump fires the postFrameCallback scheduled by didChangeDependencies.
  await tester.pump();
}

void _mockClipboard(WidgetTester tester) {
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async => null,
  );
}

void main() {
  group('EntryRevealScreen', () {
    testWidgets('shows entry name as subtitle', (tester) async {
      await _pumpEntryRevealScreen(tester, entryName: 'My Secret');

      expect(find.text('My Secret'), findsOneWidget);
    });

    testWidgets('value is obfuscated before animation completes', (tester) async {
      await _pumpEntryRevealScreen(tester, entryValue: 'hello');

      expect(find.text('hello'), findsNothing);
    });

    testWidgets('value is fully revealed after animation completes', (tester) async {
      await _pumpEntryRevealScreen(tester, entryValue: 'hello');

      await tester.pump(const Duration(milliseconds: 1600));

      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('Copy button is present before animation completes', (tester) async {
      await _pumpEntryRevealScreen(tester);

      expect(find.text('Copy'), findsOneWidget);
      expect(find.byIcon(Icons.copy), findsOneWidget);
    });

    testWidgets('tapping value during animation skips to full reveal', (tester) async {
      await _pumpEntryRevealScreen(tester, entryValue: 'hello');

      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.byType(GestureDetector).first);
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('Copy button shows Copied! after tap', (tester) async {
      _mockClipboard(tester);
      await _pumpEntryRevealScreen(tester);
      await tester.pump(const Duration(milliseconds: 1600));

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(find.text('Copied!'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsOneWidget);

      // Drain the pending 2s reset timer so the test ends cleanly.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    });

    testWidgets('Copy button resets to Copy after 2 seconds', (tester) async {
      _mockClipboard(tester);
      await _pumpEntryRevealScreen(tester);
      await tester.pump(const Duration(milliseconds: 1600));

      await tester.tap(find.text('Copy'));
      // Let the Clipboard.setData async gap complete and setState fire.
      await tester.pump();
      await tester.pump();
      expect(find.text('Copied!'), findsOneWidget);

      // Advance past the 2s reset delay and let AnimatedSwitcher rebuild.
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();

      expect(find.text('Copy'), findsOneWidget);
      expect(find.text('Copied!'), findsNothing);
    });

    testWidgets('clipboard countdown appears after copy', (tester) async {
      _mockClipboard(tester);
      await _pumpEntryRevealScreen(tester);
      await tester.pump(const Duration(milliseconds: 1600));

      await tester.tap(find.text('Copy'));
      await tester.pump();

      expect(find.textContaining('Clipboard clears in'), findsOneWidget);

      // Drain the pending 2s reset timer so the test ends cleanly.
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
    });

    testWidgets('back button is present when pushed via Navigator', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EntryRevealScreen(
                      entryName: 'Entry',
                      entryValue: 'value',
                    ),
                  ),
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pumpAndSettle();
      await tester.pump();

      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('reveal does not start during Navigator push transition', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const EntryRevealScreen(
                      entryName: 'Entry',
                      entryValue: 'abc',
                    ),
                  ),
                ),
                child: const Text('Go'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Go'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text('abc'), findsNothing);
    });
  });
}
