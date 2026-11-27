import 'package:flutter/material.dart';

/// Couleurs de PreuvCam Assureur, reprises des maquettes.
abstract final class Palette {
  static const teal = Color(0xFF0F6B5F);
  static const tealDark = Color(0xFF0A4F46);
  static const tealLight = Color(0xFFE7F3F1);
  static const ink = Color(0xFF13201E);
  static const body = Color(0xFF33413E);
  static const muted = Color(0xFF4F5E5B);
  static const background = Color(0xFFF4F7F6);
  static const border = Color(0xFFDDE5E3);
  static const track = Color(0xFFE3EAE8);

  static const okBg = Color(0xFFE6F4EA);
  static const okFg = Color(0xFF145A32);
  static const warnBg = Color(0xFFFEF0C7);
  static const warnFg = Color(0xFF7A3E06);
  static const errorBg = Color(0xFFFDECEA);
  static const errorFg = Color(0xFFA3271C);
  static const neutralBg = Color(0xFFEEF2F1);
  static const neutralFg = Color(0xFF33413E);
}

/// Largeur en dessous de laquelle on passe en mise en page compacte.
const compactWidth = 960.0;