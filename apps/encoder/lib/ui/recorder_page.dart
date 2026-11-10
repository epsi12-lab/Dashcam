import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
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
  Uploader? _uploader;
  LocalRetention? _retention;
  Directory? _segmentsDir;

  // Caméra et enregistreur, recréés à chaque retour au premier plan.
  CameraDescription? _backCamera;
  CameraController? _camera;
  DashcamRecorder? _recorder;
  bool _opening = false;
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
    _releaseCamera();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      _releaseCamera();
    } else if (state == AppLifecycleState.resumed) {
      if (_camera == null && _backCamera != null) _openCamera();
    }
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
      await _openCamera();
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
    } finally {
      _opening = false;
    }
  }

  /// Termine proprement le segment en cours, puis libère la caméra.
  Future<void> _releaseCamera() async {
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
  });

  final RecorderState state;
  final VoidCallback onToggle;
  final VoidCallback onProtect;
  final VoidCallback? onSignOut;

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