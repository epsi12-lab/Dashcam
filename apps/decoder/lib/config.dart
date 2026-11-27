/// Configuration fournie au lancement avec `--dart-define`.
/// Aucune valeur n'est codée en dur : le même code peut cibler Supabase en
/// local ou le projet hébergé dans le cloud.
class AppConfig {
  static const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'http://127.0.0.1:54321',
  );

  /// Clé publique (`publishable`) du projet Supabase.
  static const supabaseKey = String.fromEnvironment('SUPABASE_KEY');
}
