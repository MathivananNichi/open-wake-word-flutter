import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'background_toast_platform_interface.dart';

/// An implementation of [BackgroundToastPlatform] that uses method channels.
class MethodChannelBackgroundToast extends BackgroundToastPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('background_toast');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
