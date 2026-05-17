// Build/dev tool for the bundled preset NG-word asset.
//
// The committed source of truth is the *encrypted* blob
// `preset_ng_words.enc`. The plaintext `preset_ng_words.json` is
// developer-local only (git-ignored). Workflow:
//
//   1. dart run tool/ng_dict.dart decrypt   # regenerate the local .json
//   2. edit android/app/src/main/assets/preset_ng_words.json
//   3. dart run tool/ng_dict.dart encrypt   # rebuild the committed .enc
//   4. commit only the .enc
//
// `encrypt` is deterministic (salt is derived from the content), so an
// unchanged dictionary produces a byte-identical blob — no noisy diffs.
//
// This file is a dev tool and is never bundled into the app.

import 'dart:io';
import 'dart:typed_data';

import 'package:comerune/data/filter/ng_dict_cipher.dart';

const String _jsonPath = 'android/app/src/main/assets/preset_ng_words.json';
const String _encPath = 'android/app/src/main/assets/preset_ng_words.enc';

int main(List<String> args) {
  if (args.length != 1 ||
      (args.first != 'encrypt' && args.first != 'decrypt')) {
    stderr.writeln('usage: dart run tool/ng_dict.dart <encrypt|decrypt>');
    return 64; // EX_USAGE
  }

  if (args.first == 'encrypt') {
    final File src = File(_jsonPath);
    if (!src.existsSync()) {
      stderr.writeln(
        'plaintext not found: $_jsonPath\n'
        'run `dart run tool/ng_dict.dart decrypt` first to regenerate it.',
      );
      return 66; // EX_NOINPUT
    }
    final Uint8List plaintext = src.readAsBytesSync();
    final Uint8List blob = encryptNgDict(plaintext);
    File(_encPath).writeAsBytesSync(blob, flush: true);
    stdout.writeln(
      'encrypted ${plaintext.length} bytes -> $_encPath (${blob.length} bytes)',
    );
    return 0;
  }

  // decrypt
  final File enc = File(_encPath);
  if (!enc.existsSync()) {
    stderr.writeln('encrypted asset not found: $_encPath');
    return 66; // EX_NOINPUT
  }
  try {
    final Uint8List plaintext = decryptNgDict(enc.readAsBytesSync());
    File(_jsonPath).writeAsBytesSync(plaintext, flush: true);
    stdout.writeln(
      'decrypted ${enc.lengthSync()} bytes -> $_jsonPath '
      '(${plaintext.length} bytes)',
    );
    stdout.writeln(
      'NOTE: $_jsonPath is git-ignored. Never commit it — '
      'only commit the regenerated .enc.',
    );
    return 0;
  } on NgDictCipherException catch (e) {
    stderr.writeln('decrypt failed: ${e.reason}');
    return 65; // EX_DATAERR
  }
}
