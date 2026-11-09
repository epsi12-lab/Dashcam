/// Configuration fournie au lancement avec --dart-define.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');
  static const profile = String.fromEnvironment('PROFILE', defaultValue: 'real');

  static bool get isDemo => profile == 'demo';
}