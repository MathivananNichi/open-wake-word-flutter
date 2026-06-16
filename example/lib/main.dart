import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:open_wake_word/open_wake_word.dart';
import 'package:record/record.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isActivated = false;
  double _probability = 0.0;
  double _threshold = 0.44;
  final List<String> _detectionLogs = [];

  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  Timer? _pollingTimer;

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _initEngine();
  }

  Future<void> _initEngine() async {
    final success = await OpenWakeWord.init(
      melModelAssetPath: 'assets/models/melspectrogram.onnx',
      embModelAssetPath: 'assets/models/embedding_model.onnx',
      wwModelAssetPaths: [
        'assets/models/hey_t_t_20260603_111612.onnx',
        'assets/models/hey_t_t_20260603_164452.onnx',
        'assets/models/hey_t_t_20260604_130156.onnx',
        'assets/models/hey_t_t_trial19_128x3_300000_20260605_041627.onnx',
        'assets/models/HEY_T_T_v2.onnx',
        'assets/models/hey_t_t_v3.onnx',
        'assets/models/hey_t_t_v4.onnx',
        'assets/models/hey_t_t_v5.onnx',
        'assets/models/hey_t_t_v6.onnx',
        'assets/models/a_d_t_v7_ir9.onnx',
        'assets/models/hey_d_t_v7_ir9.onnx',
        'assets/models/hey_t_d_v7_ir9.onnx',
        'assets/models/hey_t_t_v7_ir9.onnx',
        'assets/models/hey_tea_tea_v7_ir9.onnx',
      ],
    );

    setState(() {
      _isInitialized = success;
    });

    if (success) {
      _startPolling();
    }
  }

  void _startPolling() {
    _pollingTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isInitialized) return;

      final prob = OpenWakeWord.getProbability();
      final activated = prob >= _threshold;

      if (prob != _probability || activated != _isActivated) {
        if (activated && !_isActivated) {
          final time = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
          final msg = "[$time] Wake word detected (prob: ${prob.toStringAsFixed(2)})";
          print(msg);
          _detectionLogs.insert(0, msg);
        }
        setState(() {
          _probability = prob;
          _isActivated = activated;
        });
      }
    });
  }

  Future<void> _toggleListening() async {
    if (_isListening) {
      await _stopListening();
    } else {
      await _startListening();
    }
  }

  Future<void> _startListening() async {
    if (await _audioRecorder.hasPermission()) {
      final stream = await _audioRecorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );

      _audioStreamSubscription = stream.listen((Uint8List bytes) {
        final int16List = Int16List(bytes.length ~/ 2);
        for (int i = 0; i < int16List.length; i++) {
          int16List[i] = (bytes[i * 2] & 0xff) | ((bytes[i * 2 + 1] & 0xff) << 8);
          if (int16List[i] >= 0x8000) {
            int16List[i] = int16List[i] - 0x10000;
          }
        }
        OpenWakeWord.processAudio(int16List);
      });

      setState(() {
        _isListening = true;
      });
    }
  }

  Future<void> _stopListening() async {
    await _audioStreamSubscription?.cancel();
    _audioStreamSubscription = null;
    await _audioRecorder.stop();
    setState(() {
      _isListening = false;
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _pollingTimer?.cancel();
    _audioStreamSubscription?.cancel();
    _audioRecorder.dispose();
    OpenWakeWord.destroy();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'OpenWakeWord FFI Demo',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6C63FF),
          brightness: Brightness.dark,
        ),
        fontFamily: 'Inter',
      ),
      home: Scaffold(
        backgroundColor: const Color(0xFF121212),
        appBar: AppBar(
          title: const Text(
            'OpenWakeWord',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.5),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          flexibleSpace: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFF6C63FF), Color(0xFF3F3D56)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
        ),
        body: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF121212), Color(0xFF1E1E2C)],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 24),
                  // Status Card
                  Container(
                    padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withOpacity(0.1), width: 1),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isInitialized ? Icons.check_circle_rounded : Icons.error_outline_rounded,
                          color: _isInitialized ? const Color(0xFF4CAF50) : const Color(0xFFF44336),
                          size: 28,
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _isInitialized ? 'Engine Ready' : 'Engine Not Initialized',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Main Listening Circle
                  Expanded(
                    flex: 4,
                    child: Center(
                      child: AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          final scale = _isListening ? 1.0 + (_pulseController.value * 0.1) : 1.0;
                          return Transform.scale(
                            scale: scale,
                            child: GestureDetector(
                              onTap: _isInitialized ? _toggleListening : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 220,
                                height: 220,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  gradient: LinearGradient(
                                    colors: _isActivated
                                        ? [const Color(0xFF4CAF50), const Color(0xFF2E7D32)]
                                        : _isListening
                                        ? [const Color(0xFF6C63FF), const Color(0xFF3F3D56)]
                                        : [const Color(0xFF2C2C2C), const Color(0xFF1A1A1A)],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  boxShadow: [
                                    if (_isActivated)
                                      BoxShadow(
                                        color: const Color(0xFF4CAF50).withOpacity(0.6),
                                        blurRadius: 40,
                                        spreadRadius: 15,
                                      )
                                    else if (_isListening)
                                      BoxShadow(
                                        color: const Color(
                                          0xFF6C63FF,
                                        ).withOpacity(0.4 * _pulseController.value),
                                        blurRadius: 30,
                                        spreadRadius: 10 * _pulseController.value,
                                      )
                                    else
                                      BoxShadow(
                                        color: Colors.black.withOpacity(0.3),
                                        blurRadius: 20,
                                        spreadRadius: 5,
                                      ),
                                  ],
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Icon(
                                        _isActivated
                                            ? Icons.check_rounded
                                            : (_isListening
                                                  ? Icons.mic_rounded
                                                  : Icons.mic_off_rounded),
                                        size: 64,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        _isActivated
                                            ? 'Detected!'
                                            : (_isListening ? 'Listening' : 'Tap to Start'),
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.9),
                                          fontSize: 18,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  SizedBox(height: 20),
                  // Listen Button (Optional now that circle is tappable, but good for clarity)
                  Center(
                    child: ElevatedButton(
                      onPressed: _isInitialized ? _toggleListening : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _isListening
                            ? Colors.white.withOpacity(0.1)
                            : const Color(0xFF6C63FF),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 18),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                      ),
                      child: Text(
                        _isListening ? 'Stop Listening' : 'Start Listening',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),

                  const SizedBox(height: 32),

                  // Controls Card
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(24),
                      border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
                    ),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Probability',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            Text(
                              _probability.toStringAsFixed(4),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Text(
                              'Threshold',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            Expanded(
                              child: SliderTheme(
                                data: SliderThemeData(
                                  activeTrackColor: const Color(0xFF6C63FF),
                                  inactiveTrackColor: Colors.white.withOpacity(0.1),
                                  thumbColor: const Color(0xFF6C63FF),
                                  overlayColor: const Color(0xFF6C63FF).withOpacity(0.2),
                                  trackHeight: 4,
                                ),
                                child: Slider(
                                  value: _threshold,
                                  min: 0.1,
                                  max: 0.99,
                                  onChanged: (val) {
                                    setState(() {
                                      _threshold = val;
                                    });
                                  },
                                ),
                              ),
                            ),
                            Text(
                              _threshold.toStringAsFixed(2),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                fontFeatures: [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Logs Section
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Detection Logs',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _detectionLogs.clear();
                          });
                        },
                        icon: const Icon(
                          Icons.delete_outline_rounded,
                          size: 18,
                          color: Colors.white54,
                        ),
                        label: const Text('Clear', style: TextStyle(color: Colors.white54)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  Expanded(
                    flex: 3,
                    child: _detectionLogs.isEmpty
                        ? Center(
                            child: Text(
                              'No detections yet',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.3),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: _detectionLogs.length,
                            itemBuilder: (context, index) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.05),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF4CAF50).withOpacity(0.2),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.mic_rounded,
                                        size: 14,
                                        color: Color(0xFF4CAF50),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Text(
                                        "${_detectionLogs.length - index}. ${_detectionLogs[index]}",
                                        style: const TextStyle(color: Colors.white70, fontSize: 14),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
