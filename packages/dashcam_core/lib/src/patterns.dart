// Motifs partagés au sein du package. Fichier interne, non exporté.

/// Motif d'un UUID en minuscules, tel que ceux générés par l'application.
const uuidSource = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

final uuidPattern = RegExp('^$uuidSource\$');

/// SHA-256 en hexadécimal minuscule, format exigé par la base.
final sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');