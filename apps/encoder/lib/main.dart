import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'config.dart';
import 'ui/login_page.dart';
import 'ui/recorder_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (AppConfig.supabaseKey.isEmpty) {
    throw StateError(
        'Clé Supabase manquante : lancer avec --dart-define=SUPABASE_KEY=<clé publique>');
  }

  await Supabase.initialize(
    url: AppConfig.supabaseUrl,
    publishableKey: AppConfig.supabaseKey,
  );
  runApp(const EncoderApp());
}

class EncoderApp extends StatelessWidget {
  const EncoderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return MaterialApp(
      title: 'Dashcam Conducteur',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: auth.onAuthStateChange,
        builder: (context, _) =>
            auth.currentSession == null ? const LoginPage() : const RecorderPage(),
      ),
    );
  }
}