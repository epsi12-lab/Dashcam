import 'package:dashcam_core/dashcam_core.dart';
import 'package:test/test.dart';

void main() {
  const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';

  group('TU-03 : nom de fichier des segments', () {
    test('le nom est construit à partir de l\'appareil et du numéro', () {
      final name = SegmentName(deviceId: deviceId, seq: 42);
      expect(name.fileName, '${deviceId}_000042.mp4');
    });

    test('un nom valide est relu correctement', () {
      final name = SegmentName.tryParse('${deviceId}_000042.mp4');
      expect(name?.deviceId, deviceId);
      expect(name?.seq, 42);
    });

    test('un numéro de plus de 6 chiffres reste lisible', () {
      final name = SegmentName(deviceId: deviceId, seq: 1234567);
      expect(SegmentName.tryParse(name.fileName)?.seq, 1234567);
    });

    test('un numéro inférieur à 1 est refusé à la construction', () {
      expect(() => SegmentName(deviceId: deviceId, seq: 0),
          throwsArgumentError);
    });

    final invalidNames = [
      'video.mp4',
      '${deviceId}_000042.mov',
      '${deviceId}_000000.mp4',
      '${deviceId}_.mp4',
      '${deviceId}_-1.mp4',
      '${deviceId.toUpperCase()}_000042.mp4',
      'pas-un-uuid_000042.mp4',
    ];
    for (final invalid in invalidNames) {
      test('le nom "$invalid" est rejeté', () {
        expect(SegmentName.tryParse(invalid), isNull);
      });
    }
  });
}