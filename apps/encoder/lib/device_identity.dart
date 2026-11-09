import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

const _key = 'device_id';

/// Identifiant du téléphone : généré au premier lancement, puis conservé.
Future<String> loadOrCreateDeviceId(SharedPreferences prefs) async {
  final existing = prefs.getString(_key);
  if (existing != null) return existing;

  final id = const Uuid().v4();
  await prefs.setString(_key, id);
  return id;
}