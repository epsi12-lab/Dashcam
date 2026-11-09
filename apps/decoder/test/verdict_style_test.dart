import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_decoder/ui/verdict_style.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('chaque verdict a un libellé, une couleur et une icône distincts', () {
    expect(Verdict.values.map((v) => v.label).toSet(), hasLength(Verdict.values.length));
    expect(Verdict.values.map((v) => v.color).toSet(), hasLength(Verdict.values.length));
    expect(Verdict.values.map((v) => v.icon).toSet(), hasLength(Verdict.values.length));
  });

  test('chaque alerte a un libellé', () {
    for (final alert in Alert.values) {
      expect(alert.label, isNotEmpty);
    }
  });

  test('le nom court montre le début de l\'appareil et le numéro', () {
    expect(shortSegmentName('3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71_000042.mp4'),
        '3f2a9c1e… n° 42');
    expect(shortSegmentName('video.mp4'), 'video.mp4');
  });
}