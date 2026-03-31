import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/connection_service.dart';
import '../services/input_service.dart';
import '../widgets/mjpeg_viewer.dart';
import '../widgets/touch_overlay.dart';
import '../widgets/trackpad_overlay.dart';
import '../widgets/modifier_keys_bar.dart';
import 'settings_screen.dart';

class DisplayScreen extends StatefulWidget {
  final ConnectionService connectionService;

  const DisplayScreen({super.key, required this.connectionService});

  @override
  State<DisplayScreen> createState() => _DisplayScreenState();
}

class _DisplayScreenState extends State<DisplayScreen> with WidgetsBindingObserver {
  bool _showToolbar = false;
  bool _showKeyboard = false;
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  bool _unlocked = false;
  List<String> _activeModifiers = [];
  final _modifierBarKey = GlobalKey<ModifierKeysBarState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _disconnect() {
    widget.connectionService.disconnect();
    Navigator.of(context).pop();
  }

  void _toggleKeyboard() {
    setState(() => _showKeyboard = !_showKeyboard);
    if (_showKeyboard) {
      _focusNode.requestFocus();
    } else {
      _focusNode.unfocus();
    }
  }

  void _onStreamError() {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Stream disconnected')),
      );
      _disconnect();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.connectionService;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          _unlocked
              ? TrackpadOverlay(
                  inputService: cs.inputService,
                  sensitivity: 1.5,
                  child: MjpegViewer(
                    streamUrl: cs.streamUrl,
                    onError: _onStreamError,
                    fit: BoxFit.contain,
                  ),
                )
              : AbsoluteTouchOverlay(
                  inputService: cs.inputService,
                  child: MjpegViewer(
                    streamUrl: cs.streamUrl,
                    onError: _onStreamError,
                    fit: BoxFit.contain,
                  ),
                ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 30,
            child: GestureDetector(
              onVerticalDragEnd: (_) {
                setState(() => _showToolbar = !_showToolbar);
              },
            ),
          ),
          if (_showToolbar)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                child: Container(
                  color: Colors.black87,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: _disconnect,
                      ),
                      Text(
                        '${cs.ip}:${cs.port}',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              _unlocked ? Icons.lock_open : Icons.lock,
                              color: _unlocked ? Colors.blue : Colors.white,
                            ),
                            onPressed: () {
                              setState(() => _unlocked = !_unlocked);
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.settings, color: Colors.white),
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(builder: (_) => const SettingsScreen()),
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(
                              _showKeyboard ? Icons.keyboard_hide : Icons.keyboard,
                              color: Colors.white,
                            ),
                            onPressed: _toggleKeyboard,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if (!_showToolbar)
            Positioned(
              top: 40,
              right: 16,
              child: GestureDetector(
                onTap: () => setState(() => _showToolbar = true),
                child: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.more_vert, color: Colors.white70, size: 20),
                ),
              ),
            ),
          if (_showKeyboard)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: Container(
                color: Colors.black87,
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ModifierKeysBar(
                      key: _modifierBarKey,
                      onModifiersChanged: (mods) {
                        setState(() => _activeModifiers = mods);
                      },
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _textController,
                            focusNode: _focusNode,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white),
                            decoration: const InputDecoration(
                              hintText: 'Type here...',
                              hintStyle: TextStyle(color: Colors.grey),
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (text) {
                              if (text.isNotEmpty) {
                                if (_activeModifiers.isNotEmpty) {
                                  cs.inputService.send(
                                    InputMessage.keyWithModifiers(text, _activeModifiers),
                                  );
                                  _modifierBarKey.currentState?.clearAll();
                                } else {
                                  cs.inputService.send(InputMessage.keyText(text));
                                }
                                _textController.clear();
                              }
                            },
                            onSubmitted: (_) {
                              cs.inputService.send(InputMessage.keyCode('enter'));
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          icon: const Icon(Icons.backspace, color: Colors.white),
                          onPressed: () {
                            cs.inputService.send(InputMessage.keyCode('backspace'));
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
