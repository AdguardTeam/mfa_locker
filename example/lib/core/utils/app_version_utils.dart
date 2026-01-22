import 'package:package_info_plus/package_info_plus.dart';

class AppVersionUtils {
  static Future<String> getAppName() async {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();

    return packageInfo.appName;
  }

  const AppVersionUtils._();
}
