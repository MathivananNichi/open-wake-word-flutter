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

class _MyAppState extends State<MyApp> {
  bool _isInitialized = false;
  bool _isListening = false;
  bool _isActivated = false;
  double _probability = 0.0;
  double _threshold = 0.5;
  final List<String> _detectionLogs = [];

  final AudioRecorder _audioRecorder = AudioRecorder();
  StreamSubscription<Uint8List>? _audioStreamSubscription;
  Timer? _pollingTimer;

  @override
  void initState() {
    super.initState();
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

          final msg = "[$time] Wake word 'Hey TT' detected (prob: ${prob.toStringAsFixed(2)})";
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
      // record 6.x: startStream returns Stream<Uint8List>
      final stream = await _audioRecorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: 16000, numChannels: 1),
      );

      _audioStreamSubscription = stream.listen((Uint8List bytes) {
        // Convert raw PCM bytes (little-endian int16) to Int16List
        final int16List = Int16List(bytes.length ~/ 2);
        for (int i = 0; i < int16List.length; i++) {
          int16List[i] = (bytes[i * 2] & 0xff) | ((bytes[i * 2 + 1] & 0xff) << 8);
          // Treat as signed 16-bit:
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
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: Scaffold(
        appBar: AppBar(
          title: const Text('OpenWakeWord FFI Demo'),
          backgroundColor: Colors.deepPurple,
          foregroundColor: Colors.white,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                _isInitialized ? Icons.check_circle : Icons.error_outline,
                color: _isInitialized ? Colors.green : Colors.red,
                size: 40,
              ),
              const SizedBox(height: 8),
              Text(
                _isInitialized ? 'Engine ready' : 'Engine not initialized',
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 32),
              ElevatedButton.icon(
                onPressed: _isInitialized ? _toggleListening : null,
                icon: Icon(_isListening ? Icons.mic_off : Icons.mic),
                label: Text(_isListening ? 'Stop Listening' : 'Start Listening'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              const SizedBox(height: 48),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 200,
                height: 200,
                decoration: BoxDecoration(
                  color: _isActivated ? Colors.green : Colors.grey.shade300,
                  shape: BoxShape.circle,
                  boxShadow: _isActivated
                      ? [
                          BoxShadow(
                            color: Colors.green.withOpacity(0.5),
                            blurRadius: 30,
                            spreadRadius: 10,
                          ),
                        ]
                      : [],
                ),
                child: Center(
                  child: Text(
                    _isActivated ? '✓' : 'Listening...',
                    style: TextStyle(
                      color: _isActivated ? Colors.white : Colors.grey,
                      fontSize: _isActivated ? 48 : 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  _detectionLogs.clear();
                  setState(() {});
                },
                child: Text("Clear"),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                ),
              ),
              Text(
                'Probability: ${_probability.toStringAsFixed(4)}',
                style: const TextStyle(fontSize: 18, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Threshold: '),
                  Slider(
                    value: _threshold,
                    min: 0.1,
                    max: 0.99,
                    onChanged: (val) {
                      setState(() {
                        _threshold = val;
                      });
                    },
                  ),
                  Text(_threshold.toStringAsFixed(2)),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'Detection Logs:',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: _detectionLogs.length,
                  itemBuilder: (context, index) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0),
                      child: Text(
                        _detectionLogs[index],
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.black87),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
