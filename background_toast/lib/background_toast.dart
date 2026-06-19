
import 'background_toast_platform_interface.dart';

class BackgroundToast {
  Future<String?> getPlatformVersion() {
    return BackgroundToastPlatform.instance.getPlatformVersion();
  }
}
