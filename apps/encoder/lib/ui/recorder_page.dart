import 'dart:async';
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

import 'palette.dart';
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
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xFFFFF4E5),
      content: Row(children: [
        Icon(Icons.verified_user_outlined, color: Palette.amber),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'Incident protégé : la minute précédente et les 30 secondes suivantes '
            'ne seront pas effacées.',
            style: TextStyle(color: Palette.warnFg, fontWeight: FontWeight.w500),
          ),
        ),
      ]),
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
              child: ColoredBox(
                color: Colors.black,
                child: camera == null
                    ? Center(
                        child: Text(_status,
                            style: const TextStyle(color: Colors.white70)))
                    : Stack(children: [
                        Center(child: CameraPreview(camera)),
                        if (recorder != null)
                          Positioned.fill(
                            child: ValueListenableBuilder<RecorderState>(
                              valueListenable: recorder.state,
                              builder: (context, s, _) => _Overlay(state: s),
                            ),
                          ),
                      ]),
              ),
            ),
            SizedBox(
              width: 300,
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

  static String _seconds(Duration? d) =>
      d == null ? '…' : '${(d.inMilliseconds / 1000).toStringAsFixed(1).replaceAll('.', ',')} s';

  @override
  Widget build(BuildContext context) {
    final pending = state.pending;
    final outlined = OutlinedButton.styleFrom(
      foregroundColor: Palette.ink,
      minimumSize: const Size.fromHeight(44),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      side: const BorderSide(color: Palette.border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    );

    return ColoredBox(
      color: Palette.panel,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const _Brand(),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: state.offline
                  ? const _Pill(label: 'Réseau', value: 'Hors ligne', icon: Icons.wifi_off,
                      bg: Palette.warnBg, fg: Palette.warnFg)
                  : const _Pill(label: 'Réseau', value: 'En ligne', icon: Icons.check,
                      bg: Palette.okBg, fg: Palette.okFg),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _Pill(
                label: 'À envoyer',
                value: pending > 1 ? '$pending empreintes' : '$pending empreinte',
                bg: Palette.neutralBg,
                fg: Palette.ink,
              ),
            ),
          ]),
          if (state.offline && state.recording) ...[
            const SizedBox(height: 8),
            const Text(
              'L\'enregistrement continue. Les empreintes partiront dès le retour du réseau.',
              style: TextStyle(fontSize: 12, color: Palette.muted),
            ),
          ],
          if (state.error != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Palette.errorBg,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(state.error!,
                  style: const TextStyle(fontSize: 13, color: Palette.errorFg)),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: state.recording ? onProtect : null,
            style: FilledButton.styleFrom(
              backgroundColor: Palette.amber,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(56),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: const Icon(Icons.shield_outlined),
            label: const Text('Protéger un incident'),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onToggle,
            style: FilledButton.styleFrom(
              backgroundColor: state.recording ? Palette.ink : Palette.teal,
              foregroundColor: Colors.white,
              minimumSize: const Size.fromHeight(48),
              textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            icon: Icon(state.recording ? Icons.stop : Icons.fiber_manual_record),
            label: Text(state.recording ? 'Arrêter l\'enregistrement' : 'Démarrer'),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: OutlinedButton(
                  onPressed: onExport, style: outlined, child: const Text('Exporter')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton(
                  onPressed: onSignOut, style: outlined, child: const Text('Déconnexion')),
            ),
          ]),
          if (state.lastGap != null || state.lastHashTime != null) ...[
            const SizedBox(height: 12),
            Text(
              'Diagnostic : coupure ${_seconds(state.lastGap)} · '
              'empreinte ${_seconds(state.lastHashTime)}',
              style: const TextStyle(fontSize: 11, color: Palette.muted),
            ),
          ],
        ],
      ),
    );
  }
}

/// Logo et nom de l'application.
class _Brand extends StatelessWidget {
  const _Brand();

  @override
  Widget build(BuildContext context) {
    return Row(children: [
      Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: Palette.teal,
          borderRadius: BorderRadius.circular(7),
        ),
        child: const Icon(Icons.shield, size: 18, color: Colors.white),
      ),
      const SizedBox(width: 8),
      const Text('PreuvCam',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Palette.ink)),
    ]);
  }
}

/// Pastille d'état : un libellé et une valeur, sur un fond coloré.
class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.value,
    required this.bg,
    required this.fg,
    this.icon,
  });

  final String label;
  final String value;
  final Color bg;
  final Color fg;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: fg)),
          Row(children: [
            if (icon != null) ...[
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(value,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: fg)),
            ),
          ]),
        ],
      ),
    );
  }
}

/// Pastilles posées sur l'image : enregistrement en cours et dernier segment.
class _Overlay extends StatelessWidget {
  const _Overlay({required this.state});

  final RecorderState state;

  @override
  Widget build(BuildContext context) {
    final seq = state.lastSeq;
    final since = state.startedAt;
    const digits = TextStyle(fontFeatures: [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(children: [
        Row(children: [
          if (state.recording && since != null)
            _Tag(children: [
              const Icon(Icons.circle, size: 10, color: Palette.rec),
              const SizedBox(width: 8),
              _EverySecond(builder: (now) {
                final d = now.difference(since);
                return Text(
                  'REC ${_two(d.inHours)}:${_two(d.inMinutes % 60)}:${_two(d.inSeconds % 60)}',
                  style: digits.copyWith(fontWeight: FontWeight.w700),
                );
              }),
            ]),
          const Spacer(),
          if (seq != null)
            _Tag(children: [
              const Icon(Icons.shield_outlined, size: 14, color: Colors.white),
              const SizedBox(width: 6),
              Text('Segment n° $seq'),
            ]),
        ]),
        const Spacer(),
        Align(
          alignment: Alignment.bottomLeft,
          child: _EverySecond(builder: (now) => Text(
                '${_two(now.day)}/${_two(now.month)} · '
                '${_two(now.hour)}:${_two(now.minute)}:${_two(now.second)}',
                style: digits.copyWith(color: Colors.white70, fontSize: 12),
              )),
        ),
      ]),
    );
  }
}

/// Étiquette sombre et translucide, lisible sur n'importe quelle image.
class _Tag extends StatelessWidget {
  const _Tag({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(999),
      ),
      child: DefaultTextStyle(
        style: const TextStyle(color: Colors.white, fontSize: 14),
        child: Row(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

/// Se redessine chaque seconde : pour le compteur et l'horloge.
class _EverySecond extends StatefulWidget {
  const _EverySecond({required this.builder});

  final Widget Function(DateTime now) builder;

  @override
  State<_EverySecond> createState() => _EverySecondState();
}

class _EverySecondState extends State<_EverySecond> {
  late final Timer _ticker;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _ticker.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(DateTime.now());
}

String _two(int n) => n.toString().padLeft(2, '0');