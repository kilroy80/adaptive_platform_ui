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
  bool _useBarDefaults = false;

  @override
  Widget build(BuildContext context) {
    final firstNormal = _alternateColors ? Colors.orange : Colors.red;
    final firstSelected = _alternateColors ? Colors.purple : Colors.blue;
    final secondNormal = _alternateColors ? Colors.red : Colors.orange;
    final secondSelected = _alternateColors ? Colors.blue : Colors.purple;

    return Scaffold(
      appBar: AppBar(title: const Text('Native Liquid Glass label probe')),
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('Use an iOS 26+ device to inspect native labels.'),
            const Text('Icons: selected green, unselected grey.'),
            Text(
              'First',
              style: TextStyle(
                color: _useBarDefaults
                    ? (_selectedIndex == 0 ? Colors.green : Colors.grey)
                    : (_selectedIndex == 0 ? firstSelected : firstNormal),
              ),
            ),
            Text(
              'Second',
              style: TextStyle(
                color: _useBarDefaults
                    ? (_selectedIndex == 1 ? Colors.green : Colors.grey)
                    : (_selectedIndex == 1 ? secondSelected : secondNormal),
              ),
            ),
            const Text('The labels below should match these reference colors.'),
            CupertinoButton(
              onPressed: () =>
                  setState(() => _alternateColors = !_alternateColors),
              child: const Text('Change explicit label colors'),
            ),
            CupertinoButton(
              onPressed: () =>
                  setState(() => _useBarDefaults = !_useBarDefaults),
              child: Text(
                _useBarDefaults
                    ? 'Use explicit label colors'
                    : 'Use bar defaults',
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: IOS26NativeTabBar(
        tint: Colors.green,
        unselectedItemTint: Colors.grey,
        selectedIndex: _selectedIndex,
        onTap: (index) => setState(() => _selectedIndex = index),
        destinations: [
          AdaptiveNavigationDestination(
            icon: 'house',
            label: 'First',
            textColor: _useBarDefaults ? null : firstNormal,
            selectedTextColor: _useBarDefaults ? null : firstSelected,
          ),
          AdaptiveNavigationDestination(
            icon: 'person',
            label: 'Second',
            textColor: _useBarDefaults ? null : secondNormal,
            selectedTextColor: _useBarDefaults ? null : secondSelected,
          ),
        ],
      ),
    );
  }
}
