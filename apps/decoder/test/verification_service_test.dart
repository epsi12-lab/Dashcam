import 'dart:convert';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_decoder/fingerprint_repository.dart';
import 'package:dashcam_decoder/verification_service.dart';
import 'package:flutter_test/flutter_test.dart';

const deviceA = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
const deviceB = '9b1d4e7a-2c3f-4a5b-8c6d-7e8f9a0b1c2d';
final t0 = DateTime.utc(2026, 11, 9, 8);
const d = Duration(seconds: 10);

Stream<List<int>> bytes(String text) => Stream.value(utf8.encode(text));

/// Imitation de Supabase : renvoie les empreintes connues et note les appels.
class FakeRepository implements FingerprintRepository {
  FakeRepository(this.stored);

  final List<StoredFingerprint> stored;
  final List<(String, int, int)> fetchCalls = [];
  final List<(String, List<int>)> freezeCalls = [];

  @override
  Future<List<StoredFingerprint>> fetchRange({
    required String deviceId,
    required int fromSeq,
    required int toSeq,
  }) async {
    fetchCalls.add((deviceId, fromSeq, toSeq));
    return stored
        .where((s) => s.deviceId == deviceId && s.seq >= fromSeq && s.seq <= toSeq)
        .toList();
  }

  @override
  Future<int> freeze({required String deviceId, required List<int> seqs}) async {
    freezeCalls.add((deviceId, seqs));
    return seqs.length;
  }
}

/// Empreintes enregistrées pour des vidéos dont on donne le contenu,
/// à partir du numéro [firstSeq].
Future<List<StoredFingerprint>> recorded(
    String deviceId, int firstSeq, List<String> contents) async {
  final result = <StoredFingerprint>[];
  var prevHash = 'f' * 64;
  for (var i = 0; i < contents.length; i++) {
    final seq = firstSeq + i;
    final hash = await sha256OfStream(bytes(contents[i]));
    final start = t0.add(d * i);
    result.add(StoredFingerprint(
      deviceId: deviceId,
      seq: seq,
      segmentHash: hash,
      prevHash: seq == 1 ? null : prevHash,
      startedAt: start,
      endedAt: start.add(d),
      receivedAt: start.add(d).add(const Duration(seconds: 2)),
      frozen: false,
    ));
    prevHash = hash;
  }
  return result;
}

PickedSegment picked(String deviceId, int seq, String content) => PickedSegment(
      fileName: SegmentName(deviceId: deviceId, seq: seq).fileName,
      content: bytes(content),
    );

void main() {
  test('EF-D02, EF-D06 : un fichier intact et un fichier retouché', () async {
    final repo = FakeRepository(await recorded(deviceA, 41, ['vidéo 41', 'vidéo 42']));
    final service = VerificationService(repository: repo);

    final results = await service.verify([
      picked(deviceA, 41, 'vidéo 41'),
      picked(deviceA, 42, 'vidéo 42 retouchée'),
    ]);

    expect(results.map((r) => r.verdict), [Verdict.authentic, Verdict.modified]);
  });

  test('EF-D03 : la plage récupérée est élargie de la marge, sans descendre sous 1',
      () async {
    final repo = FakeRepository([]);
    final service = VerificationService(repository: repo);

    await service.verify([picked(deviceA, 150, 'a'), picked(deviceA, 151, 'b')]);
    await service.verify([picked(deviceA, 5, 'c')]);

    expect(repo.fetchCalls, [(deviceA, 50, 251), (deviceA, 1, 105)]);
  });

  test('chaque appareil est récupéré séparément, et l\'ordre des fichiers est conservé',
      () async {
    final repo = FakeRepository([
      ...await recorded(deviceA, 41, ['A41']),
      ...await recorded(deviceB, 41, ['B41']),
    ]);
    final service = VerificationService(repository: repo);

    final results = await service.verify([
      picked(deviceB, 41, 'B41'),
      picked(deviceA, 41, 'A41'),
    ]);

    expect(repo.fetchCalls.map((c) => c.$1).toSet(), {deviceA, deviceB});
    expect(results.map((r) => r.fileName), [
      SegmentName(deviceId: deviceB, seq: 41).fileName,
      SegmentName(deviceId: deviceA, seq: 41).fileName,
    ]);
    expect(results.map((r) => r.verdict), everyElement(Verdict.authentic));
  });

  test('un nom de fichier invalide ne déclenche aucune requête', () async {
    final repo = FakeRepository([]);
    final service = VerificationService(repository: repo);

    final results = await service.verify(
        [PickedSegment(fileName: 'video.mp4', content: bytes('x'))]);

    expect(repo.fetchCalls, isEmpty);
    expect(results.single.verdict, Verdict.unknown);
  });

  test('la progression du hachage est signalée fichier par fichier', () async {
    final service = VerificationService(repository: FakeRepository([]));
    final progress = <(int, int)>[];

    await service.verify(
      [picked(deviceA, 1, 'a'), picked(deviceA, 2, 'b')],
      onProgress: (done, total) => progress.add((done, total)),
    );

    expect(progress, [(1, 2), (2, 2)]);
  });

  test('EF-D07 : le gel porte sur toutes les références, pas sur les inconnus', () async {
    final repo = FakeRepository(await recorded(deviceA, 41, ['vidéo 41', 'vidéo 42']));
    final service = VerificationService(repository: repo);
    final results = await service.verify([
      picked(deviceA, 41, 'vidéo 41'),
      picked(deviceA, 42, 'vidéo 42 retouchée'),
      PickedSegment(fileName: 'video.mp4', content: bytes('x')),
    ]);

    final frozen = await service.freeze(results);

    expect(repo.freezeCalls, hasLength(1));
    expect(repo.freezeCalls.single.$1, deviceA);
    expect(repo.freezeCalls.single.$2, [41, 42]);
    expect(frozen, 2);
  });
}