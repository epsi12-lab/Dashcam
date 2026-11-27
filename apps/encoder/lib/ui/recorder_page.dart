import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../config.dart';
import '../dashcam_recorder.dart';
import '../device_identity.dart';
import '../device_registry.dart';
import '../local_retention.dart';
import '../local_store.dart';
import '../segment_processor.dart';
import '../supabase_fingerprint_sender.dart';
import '../uploader.dart';

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with WidgetsBindingObserver {
  // Services, créés une fois.
  SegmentProcessor? _processor;
  LocalStore? _store;
  Uploader? _uploader;
  LocalRetention? _retention;
  Directory? _segmentsDir;
  /// Moment où l'application a cessé d'être visible.
  DateTime? _hiddenAt;

  // Caméra et enregistreur, recréés à chaque retour au premier plan.
  CameraDescription? _backCamera;
  CameraController? _camera;
  DashcamRecorder? _recorder;
  bool _opening = false;
  /// Vrai si l'enregistrement tournait quand l'application a été masquée.
  bool _resumeRecording = false;
  /// File des opérations sur la caméra : une seule à la fois, dans l'ordre.
  Future<void> _cameraOps = Future.value();
  String _status = 'Préparation…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Le téléphone est posé en paysage sur son support de pare-brise.
    SystemChrome.setPreferredOrientations([DeviceOrientation.landscapeLeft]);
    _prepare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    _enqueue(_release);
    super.dispose();
  }

    @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.inactive:
        // Perte de focus (capture d'écran, notifications, départ en arrière-plan) :
        // on termine le segment tant que la caméra est encore active.
        _enqueue(_pauseRecording);
      case AppLifecycleState.hidden:
        _hiddenAt = DateTime.now();
        _enqueue(_release);
      case AppLifecycleState.resumed:
        _enqueue(_resume);
      default:
        break;
    }
  }

  /// Termine proprement l'enregistrement en cours, en retenant qu'il tournait.
  Future<void> _pauseRecording() async {
    final recorder = _recorder;
    if (recorder == null || !recorder.state.value.recording) return;
    _resumeRecording = true;
    await recorder.stop();
    WakelockPlus.disable();
  }

  /// Rouvre la caméra si elle a été libérée, puis reprend l'enregistrement
  /// si l'absence a été courte. Après une longue absence, la reprise
  /// automatique échoue sur ce téléphone : on demande un démarrage manuel.
  Future<void> _resume() async {
    final hiddenAt = _hiddenAt;
    _hiddenAt = null;
    final longAbsence = hiddenAt != null &&
        DateTime.now().difference(hiddenAt) > const Duration(seconds: 15);

    if (_camera == null && _backCamera != null) await _openCamera();
    final recorder = _recorder;
    if (!_resumeRecording || recorder == null) return;
    _resumeRecording = false;

    if (longAbsence) {
      recorder.state.value = recorder.state.value.copyWith(
          error: 'Enregistrement interrompu pendant l\'absence. Touchez « Démarrer ».');
      return;
    }
    WakelockPlus.enable();
    await recorder.start();
  }

  Future<void> _prepare() async {
    // La session peut avoir été fermée entre-temps (rôle refusé, déconnexion).
    final client = Supabase.instance.client;
    if (client.auth.currentUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await loadOrCreateDeviceId(prefs);
      await registerDevice(client, deviceId);

      final db = await openDatabase(p.join(await getDatabasesPath(), 'encoder.db'));
      final store = await LocalStore.open(db);
      _store = store;
      final docs = await getApplicationDocumentsDirectory();
      final segmentsDir = Directory(p.join(docs.path, 'segments'));
      await segmentsDir.create(recursive: true);

      _segmentsDir = segmentsDir;
      _processor = SegmentProcessor(store: store, deviceId: deviceId);
      _uploader = Uploader(store: store, sender: SupabaseFingerprintSender(client));
      _retention = LocalRetention(
        store: store,
        deleteFile: (name) async {
          final file = File(p.join(segmentsDir.path, name));
          if (await file.exists()) await file.delete();
        },
        sizeOf: (name) async {
          final file = File(p.join(segmentsDir.path, name));
          return await file.exists() ? await file.length() : 0;
        },
        now: () => DateTime.now().toUtc(),
        retention: AppConfig.isDemo ? const Duration(minutes: 2) : const Duration(hours: 24),
        maxBytes: 2 * 1024 * 1024 * 1024, // 2 Go, soit environ 45 min en 720p
      );

      final cameras = await availableCameras();
      _backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      await _enqueue(_openCamera);
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Échec de la préparation : $e');
    }
  }

  Future<void> _openCamera() async {
    final description = _backCamera;
    if (description == null || _opening) return;
    _opening = true;
    try {
      final camera = CameraController(
        description,
        // 720p, pour la qualité de la preuve. Le débit (12 Mbit/s) est imposé
        // par le profil du constructeur : ce téléphone ignore videoBitrate.
        ResolutionPreset.high,
        enableAudio: false,
      );
      await camera.initialize();
      await camera.lockCaptureOrientation(DeviceOrientation.landscapeLeft);
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _recorder = DashcamRecorder(
          camera: camera,
          processor: _processor!,
          uploader: _uploader!,
          retention: _retention!,
          segmentsDir: _segmentsDir!,
        );
        _status = 'Prêt à enregistrer.';
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _status = 'Caméra indisponible : ${e.description}');
    } on Object catch (e) {
      if (mounted) setState(() => _status = 'Ouverture impossible : $e');
    } finally {
      _opening = false;
    }
  }

  /// Ajoute une opération à la file. Une erreur est journalisée
  /// mais ne bloque pas les opérations suivantes.
  Future<void> _enqueue(Future<void> Function() op) {
    _cameraOps = _cameraOps.then((_) async {
      try {
        await op();
      } on Object catch (e) {
        debugPrint('Opération caméra en échec : $e');
      }
    });
    return _cameraOps;
  }

  /// Termine proprement le segment en cours, puis libère la caméra.
  Future<void> _release() async {
    final recorder = _recorder;
    final camera = _camera;
    if (mounted) {
      setState(() {
        _recorder = null;
        _camera = null;
        _status = 'Caméra en pause.';
      });
    }
    WakelockPlus.disable();
    if (recorder != null) {
      await recorder.stop();
      recorder.dispose();
    }
    await camera?.dispose();
  }

  Future<void> _toggleRecording() async {
    final recorder = _recorder;
    if (recorder == null) return;
    if (recorder.state.value.recording) {
      await recorder.stop();
      WakelockPlus.disable();
    } else {
      WakelockPlus.enable();
      await recorder.start();
    }
  }

  Future<void> _protectIncident() async {
    await _retention?.protectIncident(DateTime.now().toUtc());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('Incident protégé : la minute précédente et les 30 secondes suivantes '
          'ne seront pas effacées.'),
    ));
  }

  /// Propose les incidents protégés et les 5 dernières minutes.
  Future<void> _chooseExport() async {
    final store = _store;
    if (store == null) return;
    final incidents = await store.protectedWindows();
    if (!mounted) return;

    final choice = await showModalBottomSheet<({DateTime start, DateTime end})>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
              title: Text('Exporter des segments'),
              subtitle: Text('Les fichiers sont partagés tels quels. Préférez l\'email, '
                  'Google Drive ou une copie directe : certaines messageries '
                  'recompressent les vidéos, ce qui change leur empreinte.'),
            ),
            for (final w in incidents)
              ListTile(
                leading: const Icon(Icons.shield),
                title: Text('Incident du ${_clock(w.start.add(const Duration(seconds: 60)))}'),
              ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const Text('Les 5 dernières minutes'),
              onTap: () {
                final now = DateTime.now().toUtc();
                Navigator.pop(
                    context, (start: now.subtract(const Duration(minutes: 5)), end: now));
              },
            ),
          ],
        ),
      ),
    );
    if (choice != null) await _export(store, choice.start, choice.end);
  }

  /// Partage, via le partage natif d'Android, les segments de l'intervalle.
  Future<void> _export(LocalStore store, DateTime start, DateTime end) async {
    final dir = _segmentsDir;
    if (dir == null) return;
    final messenger = ScaffoldMessenger.of(context);

    final files = <XFile>[];
    for (final segment in await store.segmentsBetween(start, end)) {
      final file = File(p.join(dir.path, segment.fileName));
      if (await file.exists()) files.add(XFile(file.path, mimeType: 'video/mp4'));
    }
    if (files.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Aucun segment enregistré sur cette période.')));
      return;
    }

    await SharePlus.instance.share(ShareParams(
      files: files,
      subject: 'PreuvCam : ${files.length} segment(s)',
    ));
  }

  /// Date et heure locales du téléphone, au format jj/mm à hh:mm.
  static String _clock(DateTime t) {
    final local = t.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)} à ${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    final recorder = _recorder;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: camera == null
                  ? Center(child: Text(_status))
                  : Center(child: CameraPreview(camera)),
            ),
            SizedBox(
              width: 260,
              child: recorder == null
                  ? Center(child: Text(_status))
                  : ValueListenableBuilder<RecorderState>(
                      valueListenable: recorder.state,
                      builder: (context, s, _) => _Panel(
                        state: s,
                        onToggle: _toggleRecording,
                        onProtect: _protectIncident,
                        onExport: s.recording ? null : _chooseExport,
                        onSignOut: s.recording
                            ? null
                            : () => Supabase.instance.client.auth.signOut(),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panneau latéral : état de l'enregistrement et commandes.
class _Panel extends StatelessWidget {
  const _Panel({
    required this.state,
    required this.onToggle,
    required this.onProtect,
    required this.onSignOut,
    required this.onExport,
  });

  final RecorderState state;
  final VoidCallback onToggle;
  final VoidCallback onProtect;
  final VoidCallback? onSignOut;
  final VoidCallback? onExport;

  @override
  Widget build(BuildContext context) {
    final gap = state.lastGap;
    final hashTime = state.lastHashTime;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: ListView(
        children: [
          Row(children: [
            Icon(Icons.circle,
                size: 14, color: state.recording ? Colors.red : Colors.grey),
            const SizedBox(width: 8),
            Text(state.recording ? 'Enregistrement' : 'À l\'arrêt',
                style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 8),
          Text('Dernier segment : ${state.lastSeq == null ? '…' : 'n° ${state.lastSeq}'}'),
          Text('En attente d\'envoi : ${state.pending}${state.offline ? ' (hors ligne)' : ''}'),
          if (gap != null) Text('Coupure entre segments : ${gap.inMilliseconds} ms'),
          if (hashTime != null) Text('Calcul de l\'empreinte : ${hashTime.inMilliseconds} ms'),
          if (state.error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(state.error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onToggle,
            icon: Icon(state.recording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(state.recording ? 'Arrêter' : 'Démarrer'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: state.recording ? onProtect : null,
            icon: const Icon(Icons.shield),
            label: const Text('Protéger un incident'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: onExport,
            icon: const Icon(Icons.ios_share),
            label: const Text('Exporter'),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onSignOut,
            icon: const Icon(Icons.logout),
            label: const Text('Se déconnecter'),
          ),
        ],
      ),
    );
  }
}