import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Motif discret de boucliers et d'empreintes, pour la bande de couleur
/// des écrans de connexion. Aucun texte n'y est superposé : le motif ne gêne
/// donc pas la lecture.
class BrandPattern extends CustomPainter {
  const BrandPattern({this.color = const Color(0x17FFFFFF)});

  /// Blanc à environ 9 % d'opacité.
  final Color color;

  static const _icons = [
    Icons.shield_outlined,
    Icons.fingerprint,
    Icons.shield_outlined,
  ];
  static const _step = 52.0;
  static const _size = 30.0;

  @override
  void paint(Canvas canvas, Size size) {
    final painters = [for (final icon in _icons) _painterFor(icon)];
    var i = 0;
    for (var y = 12.0; y < size.height; y += _step) {
      for (var x = 12.0; x < size.width; x += _step) {
        final tp = painters[i % painters.length];
        // Inclinaison entre -15° et +15°, toujours la même pour une case :
        // le motif paraît irrégulier mais ne bouge pas d'un affichage à l'autre.
        final angle = ((i * 37) % 30 - 15) * math.pi / 180;
        canvas
          ..save()
          ..translate(x + _size / 2, y + _size / 2)
          ..rotate(angle);
        tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
        canvas.restore();
        i++;
      }
    }
    for (final tp in painters) {
      tp.dispose();
    }
  }

  /// Une icône Material est un caractère d'une police : elle est donc dessinée
  /// comme du texte.
  TextPainter _painterFor(IconData icon) => TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        fontSize: _size,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();

  @override
  bool shouldRepaint(BrandPattern oldDelegate) => oldDelegate.color != color;
}
