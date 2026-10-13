import 'package:adaptive_platform_ui/adaptive_platform_ui.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

// Run on an iOS 26+ device/simulator with:
// flutter run -t lib/native_label_color_probe.dart -d <device-id>
void main() {
  runApp(const MaterialApp(home: NativeLabelColorProbe()));
}

class NativeLabelColorProbe extends StatefulWidget {
  const NativeLabelColorProbe({super.key});

  @override
  State<NativeLabelColorProbe> createState() => _NativeLabelColorProbeState();
}

class _NativeLabelColorProbeState extends State<NativeLabelColorProbe> {
  int _selectedIndex = 0;
  bool _alternateColors = false;

  @override
  Widget build(BuildContext context) {
    final normalColor = _alternateColors ? Colors.orange : Colors.grey;
    final selectedColor = _alternateColors ? Colors.purple : Colors.green;

    return Scaffold(
      appBar: AppBar(title: const Text('Native Liquid Glass label probe')),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Use an iOS 26+ device to inspect native labels.'),
            const Text(
              'Icons keep their own colors; labels use common text colors.',
            ),
            Text(
              'First',
              style: TextStyle(
                color: _selectedIndex == 0 ? selectedColor : normalColor,
              ),
            ),
            Text(
              'Second',
              style: TextStyle(
                color: _selectedIndex == 1 ? selectedColor : normalColor,
              ),
            ),
            const Text('The labels below should match these reference colors.'),
            CupertinoButton(
              onPressed: () =>
                  setState(() => _alternateColors = !_alternateColors),
              child: const Text('Change common tab colors'),
            ),
          ],
        ),
      ),
      bottomNavigationBar: IOS26NativeTabBar(
        tint: Colors.green,
        unselectedItemTint: Colors.grey,
        selectedTextColor: selectedColor,
        unselectedTextColor: normalColor,
        selectedIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        destinations: [
          AdaptiveNavigationDestination(icon: 'house', label: 'First'),
          AdaptiveNavigationDestination(icon: 'person', label: 'Second'),
        ],
      ),
    );
  }
}
