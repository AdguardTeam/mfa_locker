import 'dart:convert';

import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/model/android_config.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:flutter/material.dart';

class TPMTestScreen extends StatefulWidget {
  const TPMTestScreen({super.key});

  @override
  State<TPMTestScreen> createState() => _TPMTestScreenState();
}

class _TPMTestScreenState extends State<TPMTestScreen> {
  bool? _secureEnclaveAvailable;
  bool? _biometryAvailable;
  String _encryptedString = '';
  String _decryptedString = '';
  bool _isKeyGenerated = false;

  late final BiometricCipher _biometricCipherPlugin;
  late final TextEditingController _textController;
  late final TextEditingController _tagTextController;

  @override
  void initState() {
    super.initState();

    _biometricCipherPlugin = BiometricCipher();
    _textController = TextEditingController();
    _tagTextController = TextEditingController(text: 'test-key-tag');

    const androidConfig = AndroidConfig(
      negativeButtonText: 'Cancel',
      promptTitle: 'Use biometrics',
      promptSubtitle: 'Using biometrics for authentication',
      promptDescription: 'Biometrics description',
    );
    const config = ConfigData(
      biometricPromptTitle: 'Authentication for data signing',
      windowsDataToSign: 'Data block for signature in Windows plugin',
      androidConfig: androidConfig,
    );

    _biometricCipherPlugin.configure(config: config);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Test TPM Plugin'),
    ),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // --- Secure Enclave ---
                _buildStatusRow(
                  label: 'Secure Enclave availability: ',
                  value: _secureEnclaveAvailable == null
                      ? null
                      : _secureEnclaveAvailable!
                      ? 'Available'
                      : 'NOT available',
                  isPositive: _secureEnclaveAvailable,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _onSECheckPressed(context),
                  child: const Text('Check Secure Enclave availability'),
                ),
                const Divider(height: 32),

                // --- Biometry ---
                _buildStatusRow(
                  label: 'Biometric availability: ',
                  value: _biometryAvailable == null
                      ? null
                      : _biometryAvailable!
                      ? 'Available'
                      : 'NOT available',
                  isPositive: _biometryAvailable,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _onBiometryCheckPressed(context),
                  child: const Text('Check Biometric availability'),
                ),
                const Divider(height: 32),

                // --- Key generation ---
                _buildKeyStatusRow(),
                const SizedBox(height: 12),
                TextField(
                  controller: _tagTextController,
                  decoration: const InputDecoration(
                    labelText: 'Tag for key generation',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _onGenerateKeyPressed(context),
                  child: const Text('Generate key'),
                ),
                const Divider(height: 32),

                // --- Encryption ---
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(
                    labelText: 'Enter data to encrypt',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                _buildStatusRow(
                  label: 'Encrypted data: ',
                  value: _encryptedString.isEmpty ? null : _encryptedString,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _onEncryptPressed(context),
                  child: const Text('Encrypt data'),
                ),
                const Divider(height: 32),

                // --- Decryption ---
                _buildStatusRow(
                  label: 'Decrypted data: ',
                  value: _decryptedString.isEmpty ? null : _decryptedString,
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => _onDecryptPressed(context),
                  child: const Text('Decrypt data'),
                ),
                const Divider(height: 32),

                // --- Delete key ---
                FilledButton(
                  onPressed: () => _onDeleteKeyPressed(context),
                  child: const Text('Delete key by tag'),
                ),
                const Divider(height: 32),

                // --- 10KB test ---
                FilledButton(
                  onPressed: () => _onTest10kBytesPressed(context),
                  child: const Text('Encrypt and decrypt 10KB'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );

  @override
  void dispose() {
    _textController.dispose();
    _tagTextController.dispose();

    super.dispose();
  }

  Widget _buildStatusRow({
    required String label,
    String? value,
    bool? isPositive,
  }) => RichText(
    text: TextSpan(
      children: [
        TextSpan(
          text: label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        if (value != null)
          TextSpan(
            text: value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: isPositive == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : isPositive
                  ? Colors.green
                  : Colors.red,
            ),
          ),
      ],
    ),
  );

  Widget _buildKeyStatusRow() {
    if (_isKeyGenerated) {
      return Text(
        'Key is generated',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Colors.green,
        ),
      );
    }

    return RichText(
      text: TextSpan(
        children: [
          TextSpan(
            text: 'Key is ',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          TextSpan(
            text: 'NOT',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Colors.red,
            ),
          ),
          TextSpan(
            text: ' generated',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _onSECheckPressed(BuildContext context) async {
    try {
      final status = await _biometricCipherPlugin.getTPMStatus();
      final isSupported = status == TPMStatus.supported;

      setState(() => _secureEnclaveAvailable = isSupported);
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Check SE error: $e');
      }
    }
  }

  Future<void> _onBiometryCheckPressed(BuildContext context) async {
    try {
      final status = await _biometricCipherPlugin.getBiometryStatus();
      final isSupported = status == BiometricStatus.supported;

      setState(() => _biometryAvailable = isSupported);
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Check biometry error: $e');
      }
    }
  }

  Future<void> _onGenerateKeyPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      _showError(context, 'Enter tag for key generation');

      return;
    }

    try {
      await _biometricCipherPlugin.generateKey(tag: _tagTextController.text);
      setState(() => _isKeyGenerated = true);
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Generation key error: $e');
      }
    }
  }

  Future<void> _onEncryptPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      _showError(context, 'Enter tag for key encryption');

      return;
    }

    if (_textController.text.isEmpty) {
      _showError(context, 'Enter data for encryption');

      return;
    }

    try {
      final encryptedString = await _biometricCipherPlugin.encrypt(
        tag: _tagTextController.text,
        data: _textController.text,
      );

      setState(() => _encryptedString = encryptedString ?? '');
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Encryption error: $e');
      }
    }
  }

  Future<void> _onDecryptPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      _showError(context, 'Enter tag for key decryption');

      return;
    }

    if (_encryptedString.isEmpty) {
      _showError(context, 'Decryption data is empty! Encrypt data before decryption');

      return;
    }

    try {
      final decryptedString = await _biometricCipherPlugin.decrypt(
        tag: _tagTextController.text,
        data: _encryptedString,
      );

      setState(() => _decryptedString = decryptedString ?? '');
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Decryption error: $e');
      }
    }
  }

  Future<void> _onDeleteKeyPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      _showError(context, 'Enter tag for key deletion');

      return;
    }

    try {
      await _biometricCipherPlugin.deleteKey(
        tag: _tagTextController.text,
      );

      if (context.mounted) {
        _showSuccess(context, 'Key was deleted');
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Deletion key error: $e');
      }
    }
  }

  Future<void> _onTest10kBytesPressed(BuildContext context) async {
    try {
      if (_tagTextController.text.isEmpty) {
        _showError(context, 'Enter tag for key generation');

        return;
      }

      // 65 is the ASCII code for the character 'A'.
      List<int> bytes = List.filled(10240, 65);
      final str = utf8.decode(bytes, allowMalformed: true);

      final encryptedString = await _biometricCipherPlugin.encrypt(
        tag: _tagTextController.text,
        data: str,
      );

      if (encryptedString == null) {
        if (context.mounted) {
          _showError(context, 'Encryption failed');
        }

        return;
      }

      final decryptedString = await _biometricCipherPlugin.decrypt(
        tag: _tagTextController.text,
        data: encryptedString,
      );

      if (decryptedString == null) {
        if (context.mounted) {
          _showError(context, 'Decryption failed');
        }

        return;
      }

      final stringLength = utf8.encode(decryptedString).length;

      if (stringLength != 10240) {
        if (context.mounted) {
          _showError(context, 'Encryption failed: unexpected length $stringLength');
        }
      }

      if (decryptedString == str) {
        if (context.mounted) {
          _showSuccess(context, 'Encryption was successful');
        }
      } else {
        if (context.mounted) {
          _showError(context, 'Encryption failed: data mismatch');
        }
      }
    } catch (e) {
      if (context.mounted) {
        _showError(context, 'Encryption error: $e');
      }
    }
  }

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showSuccess(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
