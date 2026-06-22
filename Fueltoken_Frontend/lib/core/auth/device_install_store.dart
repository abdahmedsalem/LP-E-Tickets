import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// Identifiant stable de l'installation mobile.
///
/// Doctrine Patch32C:
/// - ce n'est pas un secret ;
/// - il identifie l'installation de l'application, pas une personne ;
/// - il reste stable tant que les données locales de l'app ne sont pas effacées ;
/// - un reset debug permet de simuler un nouveau device avec le même téléphone.
class DeviceInstallStore {
  DeviceInstallStore._();

  static const _kDeviceInstallUid = 'ft_device_install_uid_v1';
  static const _uuid = Uuid();

  static String currentPlatformName() {
    if (kIsWeb) return 'web';
    return defaultTargetPlatform.toString().split('.').last;
  }

  static Future<String?> read() async {
    final p = await SharedPreferences.getInstance();
    final s = p.getString(_kDeviceInstallUid);
    if (s == null || s.trim().isEmpty) return null;
    return s.trim();
  }

  static Future<String> readOrCreate() async {
    final existing = await read();
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }

    final platform = currentPlatformName();
    final value = 'ft-$platform-${_uuid.v4()}';

    final p = await SharedPreferences.getInstance();
    await p.setString(_kDeviceInstallUid, value);
    return value;
  }

  static Future<void> resetForDebug() async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_kDeviceInstallUid);
  }
}
