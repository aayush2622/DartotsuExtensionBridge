import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

class CryptoAES {
  static Future<String> encryptAESCryptoJS(
    String plainText,
    String passphrase,
  ) async {
    final salt = genRandomWithNonZero(8);
    final (keyBytes, ivBytes) = deriveKeyAndIV(passphrase.trim(), salt);

    final key = SecretKey(keyBytes);
    final algorithm = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);

    final secretBox = await algorithm.encrypt(
      utf8.encode(plainText.trim()),
      secretKey: key,
      nonce: ivBytes,
    );

    final withSalt = Uint8List.fromList(
      utf8.encode("Salted__") + salt + secretBox.cipherText,
    );

    return base64.encode(withSalt);
  }

  static Future<String> decryptAESCryptoJS(
    String encrypted,
    String passphrase,
  ) async {
    final encryptedBytesWithSalt = base64.decode(encrypted.trim());

    final salt = encryptedBytesWithSalt.sublist(8, 16);
    final encryptedBytes = encryptedBytesWithSalt.sublist(16);

    final (keyBytes, ivBytes) = deriveKeyAndIV(passphrase.trim(), salt);
    final key = SecretKey(keyBytes);

    final algorithm = AesCbc.with256bits(macAlgorithm: MacAlgorithm.empty);

    final secretBox = SecretBox(encryptedBytes, nonce: ivBytes, mac: Mac.empty);

    final clearText = await algorithm.decrypt(secretBox, secretKey: key);
    return utf8.decode(clearText);
  }

  static (Uint8List, Uint8List) deriveKeyAndIV(
    String passphrase,
    Uint8List salt,
  ) {
    final password = createUint8ListFromString(passphrase);
    Uint8List concatenatedHashes = Uint8List(0);
    Uint8List currentHash = Uint8List(0);

    while (concatenatedHashes.length < 48) {
      final preHash = Uint8List.fromList(
        (currentHash.isNotEmpty ? currentHash : <int>[]) + password + salt,
      );

      currentHash = Uint8List.fromList(crypto.md5.convert(preHash).bytes);
      concatenatedHashes = Uint8List.fromList(concatenatedHashes + currentHash);
    }

    final keyBytes = concatenatedHashes.sublist(0, 32);
    final ivBytes = concatenatedHashes.sublist(32, 48);
    return (keyBytes, ivBytes);
  }

  static Uint8List createUint8ListFromString(String s) =>
      Uint8List.fromList(s.codeUnits);

  static Uint8List genRandomWithNonZero(int seedLength) {
    final random = Random.secure();
    const randomMax = 245;
    return Uint8List.fromList(
      List.generate(seedLength, (_) => random.nextInt(randomMax) + 1),
    );
  }
}
