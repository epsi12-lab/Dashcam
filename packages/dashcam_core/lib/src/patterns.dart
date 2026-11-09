// Motifs partagés par le package. Fichier interne : il n'est pas exporté.

/// Motif d'un uuid en minuscules, comme ceux générés par l'application.
const uuidSource = '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}';

final uuidPattern = RegExp('^$uuidSource\$');

/// SHA-256 en hexadécimal minuscule : le format exigé par la base.
final sha256HexPattern = RegExp(r'^[0-9a-f]{64}$');