import 'package:dashcam_core/dashcam_core.dart';
import 'package:dashcam_encoder/fingerprint_sender.dart';
import 'package:dashcam_encoder/local_store.dart';
import 'package:dashcam_encoder/uploader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const deviceId = '3f2a9c1e-7b4d-4e8a-9f10-2c6b8d4e5a71';
final t0 = DateTime.utc(2026, 11, 9, 8);
const d = Duration(seconds: 10);

/// Imitation de Supabase, programmable test par test.
class FakeSender implements FingerprintSender {
  /// Numéros réellement enregistrés « sur le serveur », dans l'ordre.
  final List<int> stored = [];

  /// Résultat imposé pour certains numéros.
  final Map<int, SendResult> scripted = {};

  /// Simule l'absence totale de réseau.
  bool offline = false;

  @override
  Future<SendResult> send(Fingerprint fp) async {
    await Future<void>.delayed(Duration.zero); // comme un vrai appel réseau
    if (offline) return const SendResult(SendStatus.networkError);
    final result = scripted[fp.seq] ?? const SendResult(SendStatus.stored);
    if (result.status == SendStatus.stored) stored.add(fp.seq);
    return result;
  }
}

/// Stockage en mémoire contenant les segments 1 à [count], en attente d'envoi.
Future<LocalStore> storeWithPending(int count) async {
  final store = await LocalStore.open(
    await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(singleInstance: false),
    ),
  );
  var fp = Fingerprint.first(
      deviceId: deviceId, segmentHash: 1.toRadixString(16).padLeft(64, '0'),
      startedAt: t0, endedAt: t0.add(d));
  await store.recordSegment(fp);
  for (var n = 2; n <= count; n++) {
    fp = fp.next(
        segmentHash: n.toRadixString(16).padLeft(64, '0'),
        startedAt: t0.add(d * (n - 1)),
        endedAt: t0.add(d * n));
    await store.recordSegment(fp);
  }
  return store;
}

void main() {
  setUpAll(sqfliteFfiInit);

  test('EF-E05 : toutes les empreintes en attente sont envoyées, dans l\'ordre',
      () async {
    final store = await storeWithPending(3);
    final sender = FakeSender();

    final report = await Uploader(store: store, sender: sender).flush();

    expect(sender.stored, [1, 2, 3]);
    expect(report.sent, 3);
    expect(report.remaining, 0);
    expect(await store.pendingCount(), 0);
  });

  test('une file vide ne déclenche aucun envoi', () async {
    final store = await storeWithPending(0 + 1);
    await store.markUploaded(1);
    final sender = FakeSender();

    final report = await Uploader(store: store, sender: sender).flush();

    expect(sender.stored, isEmpty);
    expect(report.sent, 0);
  });

  test('EF-E06 : sans réseau, la file reste intacte, puis se vide au retour du réseau',
      () async {
    final store = await storeWithPending(3);
    final sender = FakeSender()..offline = true;
    final uploader = Uploader(store: store, sender: sender);

    final offlineReport = await uploader.flush();
    expect(offlineReport.networkUnavailable, isTrue);
    expect(offlineReport.remaining, 3);
    expect(sender.stored, isEmpty);

    sender.offline = false;
    final onlineReport = await uploader.flush();
    expect(onlineReport.remaining, 0);
    expect(sender.stored, [1, 2, 3]);
  });

  test('ENF-05 : une coupure en cours de route reprend au bon segment', () async {
    final store = await storeWithPending(3);
    final sender = FakeSender()
      ..scripted[2] = const SendResult(SendStatus.networkError);
    final uploader = Uploader(store: store, sender: sender);

    final first = await uploader.flush();
    expect(first.sent, 1);
    expect(first.remaining, 2);
    expect(sender.stored, [1]);

    sender.scripted.remove(2);
    await uploader.flush();
    expect(sender.stored, [1, 2, 3]);
  });

  test('un doublon est traité comme un succès (idempotence)', () async {
    final store = await storeWithPending(3);
    final sender = FakeSender()
      ..scripted[1] = const SendResult(SendStatus.duplicate);

    final report = await Uploader(store: store, sender: sender).flush();

    expect(report.remaining, 0);
    expect(report.error, isNull);
    expect(sender.stored, [2, 3]);
  });

  test('un refus bloque la file et est signalé, sans sauter de segment', () async {
    final store = await storeWithPending(3);
    final sender = FakeSender()
      ..scripted[2] = const SendResult(SendStatus.rejected, 'violation de contrainte');

    final report = await Uploader(store: store, sender: sender).flush();

    expect(sender.stored, [1]);
    expect(report.remaining, 2);
    expect(report.error, contains('violation de contrainte'));
    expect(report.networkUnavailable, isFalse);
  });

  test('deux vidages simultanés n\'envoient pas deux fois la même empreinte',
      () async {
    final store = await storeWithPending(3);
    final sender = FakeSender();
    final uploader = Uploader(store: store, sender: sender);

    // Les deux appels sont lancés sans attendre le premier.
    await Future.wait([uploader.flush(), uploader.flush()]);

    expect(sender.stored, [1, 2, 3]);
  });
}