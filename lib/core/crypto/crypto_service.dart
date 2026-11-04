import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/app_constants.dart';

class CryptoService {
  static final CryptoService _instance = CryptoService._internal();
  factory CryptoService() => _instance;
  CryptoService._internal();

  final _algorithm = AesGcm.with256bits();
  SecretKey? _sessionKey;
  String _nodeId = '';

  String get nodeId => _nodeId;

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    var storedNodeId = prefs.getString(AppConstants.prefNodeId);
    if (storedNodeId == null || storedNodeId.isEmpty) {
      storedNodeId = _generateRandomId();
      await prefs.setString(AppConstants.prefNodeId, storedNodeId);
    }
    _nodeId = storedNodeId;

    // Initialize standard master local key for app session
    final secretKeyBytes = List<int>.generate(32, (i) => (i * 37 + 13) % 256);
    _sessionKey = SecretKey(secretKeyBytes);
  }

  String _generateRandomId() {
    final rand = Random.secure();
    final bytes = List<int>.generate(8, (_) => rand.nextInt(256));
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
  }

  /// Encrypt a string payload with AES-GCM-256
  Future<Map<String, String>> encryptPayload(String plaintext) async {
    final secretKey = _sessionKey ?? await _algorithm.newSecretKey();
    final nonce = _algorithm.newNonce();
    final clearTextBytes = utf8.encode(plaintext);

    final secretBox = await _algorithm.encrypt(
      clearTextBytes,
      secretKey: secretKey,
      nonce: nonce,
    );

    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
      'tag': base64Encode(secretBox.mac.bytes),
    };
  }

  /// Decrypt ciphertext using nonce and tag
  Future<String> decryptPayload(Map<String, dynamic> encryptedData) async {
    try {
      final ciphertext = base64Decode(encryptedData['ciphertext'] as String);
      final nonce = base64Decode(encryptedData['nonce'] as String);
      final tag = base64Decode(encryptedData['tag'] as String);

      final secretKey = _sessionKey ?? await _algorithm.newSecretKey();
      final secretBox = SecretBox(ciphertext, nonce: nonce, mac: Mac(tag));

      final clearTextBytes = await _algorithm.decrypt(
        secretBox,
        secretKey: secretKey,
      );

      return utf8.decode(clearTextBytes);
    } catch (e) {
      // Fallback if raw text
      return encryptedData['ciphertext']?.toString() ?? 'Gagal mendekripsi';
    }
  }

  /// Generate a 4-digit SAS (Short Authentication String) PIN
  static String generatePinFromAuthToken(String token) {
    int hash = 0;
    for (int i = 0; i < token.length; i++) {
      hash = (31 * hash + token.codeUnitAt(i)) % 10000;
    }
    return hash.abs().toString().padLeft(4, '0');
  }
}

