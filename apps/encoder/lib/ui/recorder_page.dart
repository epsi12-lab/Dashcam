import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../device_identity.dart';
import '../device_registry.dart';

class RecorderPage extends StatefulWidget {
  const RecorderPage({super.key});

  @override
  State<RecorderPage> createState() => _RecorderPageState();
}

class _RecorderPageState extends State<RecorderPage> with WidgetsBindingObserver {
  CameraDescription? _backCamera;
  CameraController? _camera;
  bool _opening = false;
  String? _deviceId;
  String _status = 'Préparation…';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _prepare();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _camera?.dispose();
    super.dispose();
  }

  /// Libère la caméra quand l'application passe en arrière-plan,
  /// et la rouvre au retour, comme le recommande le plugin camera.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive) {
      final camera = _camera;
      if (camera != null) {
        setState(() {
          _camera = null;
          _status = 'Caméra en pause.';
        });
        camera.dispose();
      }
    } else if (state == AppLifecycleState.resumed) {
      if (_camera == null && _backCamera != null) _openCamera();
    }
  }

  Future<void> _prepare() async {
    // La session peut avoir été fermée entre-temps (rôle refusé, déconnexion).
    if (Supabase.instance.client.auth.currentUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await loadOrCreateDeviceId(prefs);
      await registerDevice(Supabase.instance.client, deviceId);

      final cameras = await availableCameras();
      _backCamera = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      if (mounted) setState(() => _deviceId = deviceId);
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
      final camera = CameraController(description, ResolutionPreset.high, enableAudio: false);
      await camera.initialize();
      if (!mounted) {
        await camera.dispose();
        return;
      }
      setState(() {
        _camera = camera;
        _status = 'Prêt à enregistrer.';
      });
    } on CameraException catch (e) {
      if (mounted) setState(() => _status = 'Caméra indisponible : ${e.description}');
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    final camera = _camera;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Dashcam Conducteur'),
        actions: [
          IconButton(
            tooltip: 'Se déconnecter',
            icon: const Icon(Icons.logout),
            onPressed: auth.signOut,
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: camera == null
                ? const Center(child: CircularProgressIndicator())
                : Center(child: CameraPreview(camera)),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Téléphone : ${_deviceId ?? '…'}'),
                const SizedBox(height: 4),
                Text(_status),
              ],
            ),
          ),
        ],
      ),
    );
  }
}