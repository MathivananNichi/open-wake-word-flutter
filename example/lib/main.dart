import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_wake_word/open_wake_word.dart';
import 'package:record/record.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeService();
  runApp(const MyApp());
}

Future<void> initializeService() async {
  final service = FlutterBackgroundService();

  await service.configure(
    androidConfiguration: AndroidConfiguration(
      onStart: onStart,
      autoStart: false,
      isForegroundMode: true,
      foregroundServiceTypes: [AndroidForegroundType.microphone],
    ),
    iosConfiguration: IosConfiguration(
      autoStart: false,
      onForeground: onStart,
      onBackground: onIosBackground,
    ),
  );
}

@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  return true;
}

@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  DartPluginRegistrant.ensureInitialized();
  WidgetsFlutterBinding.ensureInitialized();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings(
    '@mipmap/ic_launcher',
  );
  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );
  await flutterLocalNotificationsPlugin.initialize(settings: initializationSettings);

  service.invoke('log', {'msg': 'Service onStart started.'});

  bool success = false;
  try {
    service.invoke('log', {'msg': 'Initializing OpenWakeWord...'});
    success = await OpenWakeWord.init(
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
        'assets/models/A_T_T_v7_ir9.onnx',
        'assets/models/Hey_Didi_v7_ir9.onnx',
        'assets/models/hey_d_t_v7_ir9.onnx',
        'assets/models/hey_t_d_v7_ir9.onnx',
        'assets/models/hey_t_t_v7_ir9.onnx',
        'assets/models/hey_tea_tea_v7_ir9.onnx',
      ],
    );
    service.invoke('log', {'msg': 'OpenWakeWord init success: $success'});
  } catch (e) {
    service.invoke('log', {'msg': 'Crash during OpenWakeWord.init: $e'});
  }

  service.invoke('log', {'msg': 'OpenWakeWord init success: $success'});

  if (!success) {
    service.stopSelf();
    return;
  }

  AudioRecorder? audioRecorder;
  StreamSubscription<Uint8List>? audioStreamSubscription;

  try {
    audioRecorder = AudioRecorder();

    // The foreground UI already verified and requested the permission.
    // We bypass the background hasPermission() check because it's known to falsely return false in isolates.
    service.invoke('log', {'msg': 'Starting audio stream without checking permission again...'});
    final stream = await audioRecorder.startStream(
      const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
        audioInterruption: AudioInterruptionMode.none,
        androidConfig: AndroidRecordConfig(
          audioSource: AndroidAudioSource.voiceRecognition,
        ),
      ),
    );

    int frameCount = 0;
    audioStreamSubscription = stream.listen(
      (Uint8List bytes) {
        frameCount++;
        if (frameCount == 1 || frameCount % 100 == 0) {
          // service.invoke('log', {'msg': 'Receiving audio stream (frame $frameCount)'});
        }
        final int16List = Int16List(bytes.length ~/ 2);
        for (int i = 0; i < int16List.length; i++) {
          int16List[i] = (bytes[i * 2] & 0xff) | ((bytes[i * 2 + 1] & 0xff) << 8);
          if (int16List[i] >= 0x8000) {
            int16List[i] = int16List[i] - 0x10000;
          }
        }
        OpenWakeWord.processAudio(int16List);
      },
      onError: (e) {
        service.invoke('log', {'msg': 'Audio stream error: $e'});
      },
    );
  } catch (e) {
    service.invoke('log', {'msg': 'Crash starting AudioRecorder: $e'});
  }

  int detectionCount = 0;
  int loopCount = 0;
  double probability = 0.0;
  bool isActivated = false;
  double threshold = 0.52;

  Timer.periodic(const Duration(milliseconds: 100), (timer) async {
    loopCount++;

    final prob = OpenWakeWord.getProbability();
    final activated = prob >= threshold;

    // Force update the UI so we can see if it's alive and what the prob is
    service.invoke('update', {'probability': prob, 'isActivated': activated});
    if (activated) {
      detectionCount++;
      final time = DateTime.now().toIso8601String().split('T').last.substring(0, 8);
      final msg = "[$time] Wake word detected (prob: ${prob.toStringAsFixed(2)})";
      print(msg);

      try {
        const bgToast = MethodChannel('background_toast');
        bgToast.invokeMethod('showToast', {'msg': 'Wake Word Detected!'});
      } catch (_) {}

      flutterLocalNotificationsPlugin.show(
        id: 888,
        title: 'Listening in Background',
        body: 'Wake word detected $detectionCount times (Last at $time)',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'my_foreground',
            'MY FOREGROUND SERVICE',
            icon: 'ic_bg_service_small',
            ongoing: true,
          ),
        ),
      );

      flutterLocalNotificationsPlugin.show(
        id: 889,
        title: 'Wake Word Detected!',
        body: 'Probability: ${prob.toStringAsFixed(2)}',
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'wake_word_alerts',
            'Wake Word Alerts',
            channelDescription: 'High priority alerts for wake word detection',
            importance: Importance.max,
            priority: Priority.high,
            ticker: 'Wake Word Detected',
          ),
        ),
      );

      service.invoke('log', {'msg': msg});
    }
  });

  service.on('stopService').listen((event) async {
    await audioStreamSubscription?.cancel();
    await audioRecorder?.stop();
    audioRecorder?.dispose();
    OpenWakeWord.destroy();
    service.stopSelf();
  });

  service.on('setThreshold').listen((event) {
    print(" setThreshold  called");
    if (event != null && event['threshold'] != null) {
      print(" setThreshold  ${threshold} ${event['threshold']}");
      threshold = event['threshold'];
    }
  });
}

class MyApp extends StatefulWidget {
  const MyApp({super.key});

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> with SingleTickerProviderStateMixin {
  bool _isInitialized = true; // Service assumes handling
  bool _isListening = false;
  bool _isActivated = false;
  double _probability = 0.0;
  double _threshold = 0.52;
  final List<String> _detectionLogs = [];

  late AnimationController _pulseController;
  final service = FlutterBackgroundService();
  StreamSubscription? _updateSubscription;
  StreamSubscription? _logSubscription;

  @override
  void initState() {
    super.initState();
    _initAnimation();
    _initService();
  }

  void _initAnimation() {
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  void _initService() {
    _updateSubscription = service.on('update').listen((event) {
      if (event != null && mounted) {
        setState(() {
          _probability = (event['probability'] as num).toDouble();
          _isActivated = event['isActivated'] as bool;
        });
      }
    });

    _logSubscription = service.on('log').listen((event) {
      if (event != null && mounted) {
        final msg = event['msg'] as String;
        setState(() {
          _detectionLogs.insert(0, msg);
        });
      }
    });

    _checkServiceStatus();
  }

  Future<void> _checkServiceStatus() async {
    bool isRunning = await service.isRunning();
    setState(() {
      _isListening = isRunning;
    });
  }

  Future<void> _toggleListening() async {
    bool isRunning = await service.isRunning();
    if (isRunning) {
      service.invoke('stopService');
      setState(() {
        _isListening = false;
        _isActivated = false;
        _probability = 0.0;
      });
    } else {
      final hasPermission = await AudioRecorder().hasPermission();
      if (!hasPermission) {
        setState(() {
          _detectionLogs.insert(0, "Microphone permission denied.");
        });
        return;
      }

      final flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();
      await flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();

      await service.startService();
      // Wait a moment for service to start and apply threshold
      Future.delayed(const Duration(milliseconds: 500), () {
        print(" setThreshold  called");
        service.invoke('setThreshold', {'threshold': _threshold});
      });
      setState(() {
        _isListening = true;
      });
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _updateSubscription?.cancel();
    _logSubscription?.cancel();
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
                    child: FittedBox(
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
                                  width: 120,
                                  height: 120,
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
                                          size: 34,
                                          color: Colors.white,
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          _isActivated
                                              ? 'Detected!'
                                              : (_isListening ? 'Listening' : 'Tap to Start'),
                                          style: TextStyle(
                                            color: Colors.white.withOpacity(0.9),
                                            fontSize: 11,
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
                                    service.invoke('setThreshold', {'threshold': val});
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
                  Builder(
                    builder: (context) {
                      return ElevatedButton.icon(
                        onPressed: () {
                          showDialog(
                            context: context,
                            builder: (context) {
                              return StatefulBuilder(
                                builder: (context, setDialogState) {
                                  return AlertDialog(
                                    backgroundColor: const Color(0xFF1E1E2C),
                                    title: Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          'Detection Logs',
                                          style: TextStyle(color: Colors.white,fontSize: 17),
                                        ),
                                        TextButton.icon(
                                          onPressed: () {
                                            setState(() {
                                              _detectionLogs.clear();
                                            });
                                            setDialogState(() {});
                                          },
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                            color: Colors.white54,
                                            size: 18,
                                          ),
                                          label: const Text(
                                            'Clear',
                                            style: TextStyle(color: Colors.white54),
                                          ),
                                        ),
                                      ],
                                    ),
                                    content: SizedBox(
                                      width: double.maxFinite,
                                      height: 400,
                                      child: _detectionLogs.isEmpty
                                          ? const Center(
                                              child: Text(
                                                'No detections yet',
                                                style: TextStyle(
                                                  color: Colors.white38,
                                                  fontStyle: FontStyle.italic,
                                                ),
                                              ),
                                            )
                                          : ListView.builder(
                                              itemCount: _detectionLogs.length,
                                              itemBuilder: (context, index) {
                                                return Container(
                                                  margin: const EdgeInsets.only(bottom: 8),
                                                  padding: const EdgeInsets.symmetric(
                                                    horizontal: 16,
                                                    vertical: 12,
                                                  ),
                                                  decoration: BoxDecoration(
                                                    color: Colors.white.withOpacity(0.05),
                                                    borderRadius: BorderRadius.circular(12),
                                                  ),
                                                  child: Text(
                                                    "${_detectionLogs.length - index}. ${_detectionLogs[index]}",
                                                    style: const TextStyle(
                                                      color: Colors.white70,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('Close'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          );
                        },
                        icon: const Icon(Icons.list_alt_rounded),
                        label: Text("View Detection Logs (${_detectionLogs.length})"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.1),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                      );
                    },
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
