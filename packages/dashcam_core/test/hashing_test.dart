import 'dart:convert';
import 'dart:math';

import 'package:dashcam_core/dashcam_core.dart';
import 'package:test/test.dart';

void main() {
  group('TU-01 : valeurs de référence du SHA-256 (NIST)', () {
    test('entrée vide', () async {
      final hash = await sha256OfStream(Stream.value(<int>[]));
      expect(hash,
          'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855');
    });

    test('"abc"', () async {
      final hash = await sha256OfStream(Stream.value(utf8.encode('abc')));
      expect(hash,
          'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
    });
  });

  group('TU-02 : le hash ne dépend pas du découpage en morceaux', () {
    test('un seul morceau ou des morceaux de 4 Ko donnent le même hash', () async {
      final data = List<int>.generate(100000, (i) => i % 256);

      final whole = await sha256OfStream(Stream.value(data));

      final chunks = Stream.fromIterable([
        for (var i = 0; i < data.length; i += 4096)
          data.sublist(i, min(i + 4096, data.length)),
      ]);
      final chunked = await sha256OfStream(chunks);

      expect(chunked, whole);
    });
  });
}