import 'package:flutter/material.dart';

class ModifierKeysBar extends StatefulWidget {
  final void Function(List<String> activeModifiers) onModifiersChanged;

  const ModifierKeysBar({super.key, required this.onModifiersChanged});

  @override
  State<ModifierKeysBar> createState() => ModifierKeysBarState();
}

class ModifierKeysBarState extends State<ModifierKeysBar> {
  final Set<String> _active = {};

  List<String> get activeModifiers => _active.toList();

  void clearAll() {
    setState(() => _active.clear());
    widget.onModifiersChanged([]);
  }

  void _toggle(String mod) {
    setState(() {
      if (_active.contains(mod)) {
        _active.remove(mod);
      } else {
        _active.add(mod);
      }
    });
    widget.onModifiersChanged(_active.toList());
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _buildKey('Cmd', 'cmd'),
        _buildKey('Ctrl', 'ctrl'),
        _buildKey('Alt', 'alt'),
        _buildKey('Shift', 'shift'),
      ],
    );
  }

  Widget _buildKey(String label, String mod) {
    final isActive = _active.contains(mod);
    return GestureDetector(
      onTap: () => _toggle(mod),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.grey[800],
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.grey[400],
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
            fontSize: 14,
          ),
        ),
      ),
    );
  }
}
