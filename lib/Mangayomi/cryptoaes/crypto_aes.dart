import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:blockchain_utils/blockchain_utils.dart';
import 'package:crypto/crypto.dart' as crypto;

class CryptoAES {
  static String encryptAESCryptoJS(String plainText, String passphrase) {
    final salt = _genRandomWithNonZero(8);
    final (key, iv) = _deriveKeyAndIV(passphrase.trim(), salt);

    // PKCS7 padding
    final data = utf8.encode(plainText.trim());
    final padLength = 16 - (data.length % 16);
    final padded = Uint8List.fromList([
      ...data,
      ...List.filled(padLength, padLength),
    ]);

    final aes = AES(key);
    final encrypted = Uint8List(padded.length);
    Uint8List prev = iv;

    for (var i = 0; i < padded.length; i += 16) {
      final block = xorBlocks(padded.sublist(i, i + 16), prev);

      // FIX: cast List<int> -> Uint8List
      final cipher = Uint8List.fromList(aes.encryptBlock(block));

      encrypted.setRange(i, i + 16, cipher);
      prev = cipher;
    }

    final out = Uint8List.fromList(utf8.encode("Salted__") + salt + encrypted);
    return base64.encode(out);
  }

  static String decryptAESCryptoJS(String encryptedBase64, String passphrase) {
    final bytes = base64.decode(encryptedBase64.trim());
    final salt = bytes.sublist(8, 16);
    final encrypted = bytes.sublist(16);

    final (key, iv) = _deriveKeyAndIV(passphrase.trim(), salt);

    final aes = AES(key);
    final decrypted = Uint8List(encrypted.length);
    Uint8List prev = iv;

    for (var i = 0; i < encrypted.length; i += 16) {
      final block = encrypted.sublist(i, i + 16);

      // FIX: cast List<int> -> Uint8List
      final plain = Uint8List.fromList(aes.decryptBlock(block));

      final xored = xorBlocks(plain, prev);
      decrypted.setRange(i, i + 16, xored);
      prev = block;
    }

    // Remove PKCS7
    final pad = decrypted.last;
    return utf8.decode(decrypted.sublist(0, decrypted.length - pad));
  }

  static (Uint8List, Uint8List) _deriveKeyAndIV(
    String passphrase,
    Uint8List salt,
  ) {
    final password = Uint8List.fromList(utf8.encode(passphrase));
    Uint8List concatenated = Uint8List(0);
    Uint8List current = Uint8List(0);

    while (concatenated.length < 48) {
      final pre = Uint8List.fromList([...current, ...password, ...salt]);
      current = Uint8List.fromList(crypto.md5.convert(pre).bytes);
      concatenated = Uint8List.fromList([...concatenated, ...current]);
    }

    final key = concatenated.sublist(0, 32);
    final iv = concatenated.sublist(32, 48);
    return (key, iv);
  }

  static Uint8List xorBlocks(Uint8List a, Uint8List b) {
    final res = Uint8List(a.length);
    for (int i = 0; i < a.length; i++) {
      res[i] = a[i] ^ b[i];
    }
    return res;
  }

  static Uint8List _genRandomWithNonZero(int len) {
    final rnd = Random.secure();
    return Uint8List.fromList(List.generate(len, (_) => rnd.nextInt(245) + 1));
  }
}
