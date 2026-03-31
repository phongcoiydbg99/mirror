import 'package:flutter/material.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  String _quality = 'medium';
  double _sensitivity = 1.5;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ListTile(
            title: const Text('Stream Quality'),
            subtitle: Text(_quality),
            trailing: DropdownButton<String>(
              value: _quality,
              items: const [
                DropdownMenuItem(value: 'low', child: Text('Low')),
                DropdownMenuItem(value: 'medium', child: Text('Medium')),
                DropdownMenuItem(value: 'high', child: Text('High')),
              ],
              onChanged: (v) {
                if (v != null) setState(() => _quality = v);
              },
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('Trackpad Sensitivity'),
            subtitle: Text('${_sensitivity.toStringAsFixed(1)}x'),
            trailing: SizedBox(
              width: 150,
              child: Slider(
                value: _sensitivity,
                min: 1.0,
                max: 3.0,
                divisions: 4,
                label: '${_sensitivity.toStringAsFixed(1)}x',
                onChanged: (v) {
                  setState(() => _sensitivity = v);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
