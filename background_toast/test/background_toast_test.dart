import 'package:flutter_test/flutter_test.dart';
import 'package:background_toast/background_toast.dart';
import 'package:background_toast/background_toast_platform_interface.dart';
import 'package:background_toast/background_toast_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBackgroundToastPlatform
    with MockPlatformInterfaceMixin
    implements BackgroundToastPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final BackgroundToastPlatform initialPlatform = BackgroundToastPlatform.instance;

  test('$MethodChannelBackgroundToast is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBackgroundToast>());
  });

  test('getPlatformVersion', () async {
    BackgroundToast backgroundToastPlugin = BackgroundToast();
    MockBackgroundToastPlatform fakePlatform = MockBackgroundToastPlatform();
    BackgroundToastPlatform.instance = fakePlatform;

    expect(await backgroundToastPlugin.getPlatformVersion(), '42');
  });
}
