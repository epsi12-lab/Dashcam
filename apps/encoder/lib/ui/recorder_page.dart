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

class _RecorderPageState extends State<RecorderPage> {
  String? _deviceId;
  String _status = 'Enregistrement du téléphone…';

  @override
  void initState() {
    super.initState();
    _registerPhone();
  }
    
Future<void> _registerPhone() async {
    // La session peut avoir été fermée entre-temps (rôle refusé, déconnexion).
    if (Supabase.instance.client.auth.currentUser == null) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = await loadOrCreateDeviceId(prefs);
      await registerDevice(Supabase.instance.client, deviceId);
      if (mounted) {
        setState(() {
          _deviceId = deviceId;
          _status = 'Téléphone enregistré.';
        });
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _status = 'Échec de l\'enregistrement : $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
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
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Connecté : ${auth.currentUser?.email ?? ''}'),
            const SizedBox(height: 8),
            Text('Téléphone : ${_deviceId ?? '…'}'),
            const SizedBox(height: 8),
            Text(_status),
          ],
        ),
      ),
    );
  }
}