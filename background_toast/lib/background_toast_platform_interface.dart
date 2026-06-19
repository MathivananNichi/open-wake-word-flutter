import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'background_toast_method_channel.dart';

abstract class BackgroundToastPlatform extends PlatformInterface {
  /// Constructs a BackgroundToastPlatform.
  BackgroundToastPlatform() : super(token: _token);

  static final Object _token = Object();

  static BackgroundToastPlatform _instance = MethodChannelBackgroundToast();

  /// The default instance of [BackgroundToastPlatform] to use.
  ///
  /// Defaults to [MethodChannelBackgroundToast].
  static BackgroundToastPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BackgroundToastPlatform] when
  /// they register themselves.
  static set instance(BackgroundToastPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
