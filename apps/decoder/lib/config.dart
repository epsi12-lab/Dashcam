/// Configuration fournie au lancement avec --dart-define.
/// Rien n'est écrit en dur : le même code peut viser Supabase local
/// ou le projet du cloud.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  /// Clé publique (publishable) du projet Supabase.
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');

  /// « real » (valeurs de la spécification) ou « demo » (durées réduites).
  static const profile = String.fromEnvironment('PROFILE', defaultValue: 'real');

  static bool get isDemo => profile == 'demo';
}