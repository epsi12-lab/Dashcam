import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:camera/camera.dart';
import 'package:dashcam_core/dashcam_core.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'local_retention.dart';
import 'segment_processor.dart';
import 'uploader.dart';

/// État de l'enregistrement, affiché par l'écran.
@immutable
class RecorderState {
  const RecorderState({
    this.recording = false,
    this.lastSeq,
    this.pending = 0,
    this.offline = false,
    this.error,
    this.lastGap,
    this.lastHashTime,
  });

  final bool recording;
  final int? lastSeq;
  final int pending;
  final bool offline;
  final String? error;

  /// Temps mort entre la fin d'un segment et le début du suivant.
  final Duration? lastGap;

  /// Durée du calcul de l'empreinte du dernier segment.
  final Duration? lastHashTime;

  RecorderState copyWith({
    bool? recording,
    int? lastSeq,
    int? pending,
    bool? offline,
    String? error,
    bool clearError = false,
    Duration? lastGap,
    Duration? lastHashTime,
  }) =>
      RecorderState(
        recording: recording ?? this.recording,
        lastSeq: lastSeq ?? this.lastSeq,
        pending: pending ?? this.pending,
        offline: offline ?? this.offline,
        error: clearError ? null : (error ?? this.error),
        lastGap: lastGap ?? this.lastGap,
        lastHashTime: lastHashTime ?? this.lastHashTime,
      );
}

/// Enregistre la vidéo en segments enchaînés et traite chacun d'eux :
/// empreinte, rangement du fichier, envoi, purge locale.
class DashcamRecorder {
  DashcamRecorder({
    required this.camera,
    required this.processor,
    required this.uploader,
    required this.retention,
    required this.segmentsDir,
    this.segmentDuration = const Duration(seconds: 10),
  });

  final CameraController camera;
  final SegmentProcessor processor;
  final Uploader uploader;
  final LocalRetention retention;
  final Directory segmentsDir;
  final Duration segmentDuration;

  final state = ValueNotifier(const RecorderState());

  bool _running = false;
  Timer? _timer;
  DateTime? _segmentStart;
  DateTime? _previousEnd;

  /// Traitements en cours, enchaînés : un segment à la fois, dans l'ordre.
  Future<void> _pending = Future.value();

  Future<void> start() async {
    if (_running) return;
    _running = true;
    state.value = state.value.copyWith(recording: true, clearError: true);
    try {
      await _startSegment();
    } on CameraException catch (e) {
      _fail('Démarrage impossible : ${e.description}');
    }
  }

  /// Arrête l'enregistrement en terminant proprement le segment en cours.
  Future<void> stop() async {
    if (!_running) return;
    _running = false;
    _timer?.cancel();
    try {
      if (camera.value.isRecordingVideo) await _closeSegment();
    } on CameraException catch (e) {
      state.value = state.value.copyWith(error: 'Arrêt incomplet : ${e.description}');
    }
    await _pending;
    state.value = state.value.copyWith(recording: false);
  }

  void dispose() {
    _timer?.cancel();
    state.dispose();
  }

  Future<void> _startSegment() async {
    await camera.startVideoRecording();
    final start = DateTime.now().toUtc();
    final previousEnd = _previousEnd;
    if (previousEnd != null) {
      state.value = state.value.copyWith(lastGap: start.difference(previousEnd));
    }
    _segmentStart = start;
    _timer = Timer(segmentDuration, _rollSegment);
  }

  Future<void> _rollSegment() async {
    if (!_running) return;
    try {
      await _closeSegment();
      if (_running) await _startSegment();
    } on CameraException catch (e) {
      _fail('Erreur de la caméra : ${e.description}');
    }
  }

  Future<void> _closeSegment() async {
    final file = await camera.stopVideoRecording();
    final end = DateTime.now().toUtc();
    final start = _segmentStart!;
    _previousEnd = end;
    _pending = _pending.then((_) => _processSegment(file.path, start, end));
  }

  Future<void> _processSegment(String path, DateTime start, DateTime end) async {
    try {
      // Hachage dans un isolate : l'aperçu de la caméra ne fige pas.
      final watch = Stopwatch()..start();
      final hash = await Isolate.run(() => sha256OfStream(File(path).openRead()));
      final hashTime = watch.elapsed;

      final fp = await processor.record(segmentHash: hash, startedAt: start, endedAt: end);
      final name = SegmentName(deviceId: fp.deviceId, seq: fp.seq).fileName;
      await _move(path, p.join(segmentsDir.path, name));
      state.value = state.value.copyWith(lastSeq: fp.seq, lastHashTime: hashTime);

      final report = await uploader.flush();
      await retention.run();
      state.value = state.value.copyWith(
        pending: report.remaining,
        offline: report.networkUnavailable,
        error: report.error,
        clearError: report.error == null,
      );
    } on Object catch (e) {
      // Un segment en échec ne doit pas bloquer les suivants : on l'affiche.
      state.value = state.value.copyWith(error: 'Segment non traité : $e');
    }
  }

  void _fail(String message) {
    _running = false;
    _timer?.cancel();
    state.value = state.value.copyWith(recording: false, error: message);
  }

  static Future<void> _move(String from, String to) async {
    try {
      await File(from).rename(to);
    } on FileSystemException {
      // Dossiers sur des partitions différentes : copie puis suppression.
      await File(from).copy(to);
      await File(from).delete();
    }
  }
}