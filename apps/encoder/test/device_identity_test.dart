import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/device_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('l\'identifiant est créé une fois, puis toujours le même', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();

    final first = await loadOrCreateDeviceId(prefs);
    final second = await loadOrCreateDeviceId(prefs);

    expect(second, first);
    // Accepté par SegmentName : uuid en minuscules.
    expect(() => SegmentName(deviceId: first, seq: 1), returnsNormally);
  });
}