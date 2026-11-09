import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = Supabase.instance.client.auth;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppConfig.isDemo ? 'Dashcam Assureur (démo)' : 'Dashcam Assureur'),
          actions: [
            Center(child: Text(auth.currentUser?.email ?? '')),
            IconButton(
              tooltip: 'Se déconnecter',
              icon: const Icon(Icons.logout),
              onPressed: auth.signOut,
            ),
          ],
          bottom: const TabBar(tabs: [
            Tab(icon: Icon(Icons.verified_user), text: 'Vérification'),
            Tab(icon: Icon(Icons.sensors), text: 'Suivi en direct'),
          ]),
        ),
        body: const TabBarView(children: [
          Center(child: Text('Écran de vérification : prochaine étape')),
          Center(child: Text('Suivi en direct : étape suivante')),
        ]),
      ),
    );
  }
}