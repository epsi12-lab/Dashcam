import 'dart:convert';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:sqflite/sqflite.dart';

/// Stockage local de l'encodeur : état de la chaîne, file d'attente des
/// empreintes à envoyer, et liste des segments enregistrés.
class LocalStore {
  LocalStore._(this._db);

  final Database _db;

  /// Prépare les tables si besoin et renvoie le stockage.
  static Future<LocalStore> open(Database db) async {
    await db.execute('''
      create table if not exists chain_state (
        id integer primary key check (id = 1),
        last_fingerprint text not null
      )''');
    await db.execute('''
      create table if not exists upload_queue (
        seq integer primary key,
        payload text not null
      )''');
        await db.execute('''
      create table if not exists segments (
        seq integer primary key,
        file_name text not null,
        started_at_ms integer not null,
        ended_at_ms integer not null
      )''');
    await db.execute('''
      create table if not exists protected_windows (
        id integer primary key autoincrement,
        starts_at_ms integer not null,
        ends_at_ms integer not null
      )''');
    return LocalStore._(db);
  }

  /// Dernière empreinte produite, ou `null` si aucun segment n'a été enregistré.
  Future<Fingerprint?> lastFingerprint() async {
    final rows = await _db.query('chain_state', where: 'id = 1');
    if (rows.isEmpty) return null;
    return _decode(rows.single['last_fingerprint']! as String);
  }

  /// Enregistre un segment : chaîne, file d'attente et liste des segments
  /// sont mises à jour ensemble, ou pas du tout.
  Future<void> recordSegment(Fingerprint fp) async {
    final json = fp.toInsertJson();
    final payload = jsonEncode(json);

    await _db.transaction((txn) async {
      await txn.insert(
        'chain_state',
        {'id': 1, 'last_fingerprint': payload},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      await txn.insert('upload_queue', {'seq': fp.seq, 'payload': payload});
            await txn.insert('segments', {
        'seq': fp.seq,
        'file_name': SegmentName(deviceId: fp.deviceId, seq: fp.seq).fileName,
        'started_at_ms': fp.startedAt.millisecondsSinceEpoch,
        'ended_at_ms': fp.endedAt.millisecondsSinceEpoch,
      });
    });
  }

  /// Empreintes en attente d'envoi, dans l'ordre des numéros.
  Future<List<Fingerprint>> pendingUploads({int? limit}) async {
    final rows = await _db.query('upload_queue', orderBy: 'seq', limit: limit);
    return [for (final row in rows) _decode(row['payload']! as String)];
  }

  /// Nombre d'empreintes en attente d'envoi.
  Future<int> pendingCount() async =>
      Sqflite.firstIntValue(await _db.rawQuery('select count(*) from upload_queue')) ?? 0;

  /// Retire une empreinte de la file une fois sa réception confirmée.
  Future<void> markUploaded(int seq) async {
    await _db.delete('upload_queue', where: 'seq = ?', whereArgs: [seq]);
  }

  /// Noms des fichiers des segments enregistrés, dans l'ordre.
  Future<List<String>> segmentFileNames() async {
    final rows = await _db.query('segments', columns: ['file_name'], orderBy: 'seq');
    return [for (final row in rows) row['file_name']! as String];
  }

    /// Enregistre une fenêtre de temps dont les segments ne seront jamais purgés.
  Future<void> addProtectedWindow(DateTime start, DateTime end) async {
    await _db.insert('protected_windows', {
      'starts_at_ms': start.millisecondsSinceEpoch,
      'ends_at_ms': end.millisecondsSinceEpoch,
    });
  }

  /// Segments terminés avant [cutoff] et ne chevauchant aucune fenêtre protégée.
  Future<List<({int seq, String fileName})>> expiredSegments(DateTime cutoff) =>
      _unprotectedSegments(endedBefore: cutoff);

  /// Tous les segments ne chevauchant aucune fenêtre protégée, du plus ancien
  /// au plus récent.
  Future<List<({int seq, String fileName})>> unprotectedSegments() =>
      _unprotectedSegments();

  Future<List<({int seq, String fileName})>> _unprotectedSegments({
    DateTime? endedBefore,
  }) async {
    final rows = await _db.rawQuery('''
      select seq, file_name from segments s
      where (? is null or s.ended_at_ms < ?)
        and not exists (
          select 1 from protected_windows w
          where w.starts_at_ms < s.ended_at_ms
            and w.ends_at_ms > s.started_at_ms
        )
      order by seq''', [
      endedBefore?.millisecondsSinceEpoch,
      endedBefore?.millisecondsSinceEpoch,
    ]);
    return [
      for (final row in rows)
        (seq: row['seq']! as int, fileName: row['file_name']! as String),
    ];
  }

  /// Retire un segment de la liste, une fois son fichier supprimé.
  Future<void> removeSegment(int seq) async {
    await _db.delete('segments', where: 'seq = ?', whereArgs: [seq]);
  }

  static Fingerprint _decode(String payload) =>
      Fingerprint.fromInsertJson(jsonDecode(payload) as Map<String, Object?>);
}