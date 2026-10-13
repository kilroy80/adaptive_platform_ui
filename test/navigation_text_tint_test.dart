import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

TextStyle labelStyle(WidgetTester tester, String label) =>
    tester.renderObject<RenderParagraph>(find.text(label)).text.style!;

void main() {
  testWidgets('Android common label colors preserve typography', (
    tester,
  ) async {
    var selected = 0;
    var selectedColor = Colors.red;
    Color? selectedTextColor = Colors.green;
    Color? unselectedTextColor = Colors.orange;
    late StateSetter update;
    final themedLabels = WidgetStateProperty.resolveWith<TextStyle?>(
      (states) => TextStyle(
        color: states.contains(WidgetState.selected)
            ? Colors.green
            : Colors.orange,
        fontSize: 17,
        fontWeight: FontWeight.w700,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(
          navigationBarTheme: NavigationBarThemeData(
            labelTextStyle: themedLabels,
          ),
        ),
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AdaptiveScaffold(
              body: const SizedBox(),
              bottomNavigationBar: AdaptiveBottomNavigationBar(
                selectedIndex: selected,
                onTap: (index) => setState(() => selected = index),
                selectedItemColor: selectedColor,
                selectedTextColor: selectedTextColor,
                unselectedTextColor: unselectedTextColor,
                unselectedItemColor: Colors.blue,
                items: [
                  const AdaptiveNavigationDestination(
                    icon: Icons.home,
                    label: 'Tinted',
                  ),
                  AdaptiveNavigationDestination(
                    icon: Icons.person,
                    label: 'Theme',
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(labelStyle(tester, 'Tinted').color, Colors.green);
    expect(labelStyle(tester, 'Theme').color, Colors.orange);
    expect(labelStyle(tester, 'Tinted').fontSize, 17);
    expect(labelStyle(tester, 'Tinted').fontWeight, FontWeight.w700);
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(labelStyle(tester, 'Tinted').color, Colors.orange);
    expect(labelStyle(tester, 'Theme').color, Colors.green);
    update(() {
      selectedColor = Colors.purple;
      selectedTextColor = null;
      unselectedTextColor = null;
    });
    await tester.pumpAndSettle();
    expect(labelStyle(tester, 'Theme').color, Colors.purple);
    expect(labelStyle(tester, 'Tinted').color, Colors.blue);
    expect(labelStyle(tester, 'Theme').fontSize, 17);
  });

  testWidgets('Android unset colors retain stateful theme defaults', (
    tester,
  ) async {
    for (final selectedColor in [null, Colors.red]) {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            navigationBarTheme: NavigationBarThemeData(
              labelTextStyle: WidgetStateProperty.resolveWith(
                (states) => TextStyle(
                  color: states.contains(WidgetState.selected)
                      ? Colors.green
                      : Colors.orange,
                ),
              ),
            ),
          ),
          home: AdaptiveScaffold(
            body: const SizedBox(),
            bottomNavigationBar: AdaptiveBottomNavigationBar(
              selectedIndex: 0,
              onTap: (_) {},
              selectedItemColor: selectedColor,
              unselectedItemColor: selectedColor == null ? Colors.blue : null,
              items: const [
                AdaptiveNavigationDestination(
                  icon: Icons.home,
                  label: 'Selected',
                ),
                AdaptiveNavigationDestination(
                  icon: Icons.person,
                  label: 'Unselected',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        labelStyle(tester, 'Selected').color,
        selectedColor ?? Colors.green,
      );
      expect(
        labelStyle(tester, 'Unselected').color,
        selectedColor == null ? Colors.blue : Colors.orange,
      );
    }
  });

  testWidgets('Cupertino labels use common bar colors', (tester) async {
    var selected = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: CupertinoTheme(
          data: const CupertinoThemeData(primaryColor: Colors.green),
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: IOS26NativeTabBar(
                selectedIndex: selected,
                onTap: (index) => setState(() => selected = index),
                tint: Colors.red,
                unselectedItemTint: Colors.blue,
                selectedTextColor: Colors.green,
                unselectedTextColor: Colors.orange,
                destinations: const [
                  AdaptiveNavigationDestination(
                    icon: Icons.home,
                    label: 'Tinted',
                  ),
                  AdaptiveNavigationDestination(
                    icon: Icons.person,
                    label: 'Theme',
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(labelStyle(tester, 'Tinted').color, Colors.green);
    expect(
      labelStyle(tester, 'Theme').color!.toARGB32(),
      Colors.orange.toARGB32(),
    );
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();
    expect(labelStyle(tester, 'Tinted').color, Colors.orange);
    expect(labelStyle(tester, 'Theme').color, Colors.green);
  });
}
