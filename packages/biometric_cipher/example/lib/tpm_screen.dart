import 'package:flutter/material.dart';
import 'package:biometric_cipher/data/biometric_status.dart';
import 'package:biometric_cipher/data/model/android_config.dart';
import 'package:biometric_cipher/data/model/config_data.dart';
import 'package:biometric_cipher/data/tpm_status.dart';
import 'package:biometric_cipher/biometric_cipher.dart';
import 'package:biometric_cipher/data/tpm_key_info.dart';

class TPMScreen extends StatefulWidget {
  const TPMScreen({super.key});

  @override
  State<TPMScreen> createState() => _TPMScreenState();
}

class _TPMScreenState extends State<TPMScreen> {
  final String tag = 'key_tag';
  bool? _secureEnclaveAvailable;
  bool? _biometricAvailable;
  String _encryptedString = '';
  String _decryptedString = '';
  bool _isKeyGenerated = false;
  int? _tpmVersion;
  List<TpmKeyInfo> _tpmKeys = [];
  String _universalEncryptedString = '';
  String _universalDecryptedString = '';

  late final BiometricCipher _biometricCipherPlugin;
  late final TextEditingController _textController;
  late final TextEditingController _tagTextController;

  @override
  void initState() {
    super.initState();

    _biometricCipherPlugin = BiometricCipher();
    _textController = TextEditingController();
    _tagTextController = TextEditingController();
    _tagTextController.text = tag;

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
    appBar: AppBar(title: const Text('Plugin example app')),
    body: SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 20),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 20),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Secure Enclave availability: ', style: Theme.of(context).textTheme.labelLarge),
                      if (_secureEnclaveAvailable != null)
                        TextSpan(
                          text: _secureEnclaveAvailable!
                              ? 'Secure Enclave is available on this device'
                              : 'Secure Enclave is NOT available on this device',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _onSECheckPressed(context),
                  child: const Text('Check Secure Enclave availability'),
                ),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Biometric availability: ', style: Theme.of(context).textTheme.labelLarge),
                      if (_biometricAvailable != null)
                        TextSpan(
                          text: _biometricAvailable!
                              ? 'Biometric is available on this device'
                              : 'Biometric is NOT available on this device',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _onBiometricCheckPressed(context),
                  child: const Text('Check Biometric availability'),
                ),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      if (_isKeyGenerated)
                        TextSpan(text: 'Key is generated', style: Theme.of(context).textTheme.labelLarge),
                      if (!_isKeyGenerated) ...[
                        TextSpan(text: 'Key is ', style: Theme.of(context).textTheme.labelLarge),
                        TextSpan(
                          text: 'NOT',
                          style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.red),
                        ),
                        TextSpan(text: ' generated', style: Theme.of(context).textTheme.labelLarge),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _tagTextController,
                  decoration: const InputDecoration(labelText: 'Tag for key generation'),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => _onGenerateKeyPressed(context), child: const Text('Generate key')),
                const Divider(),
                TextField(
                  controller: _textController,
                  decoration: const InputDecoration(label: Text('Enter data to encrypt')),
                ),
                const SizedBox(height: 20),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Encrypted data: ', style: Theme.of(context).textTheme.labelLarge),
                      TextSpan(text: _encryptedString, style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => _onEncryptedPressed(context), child: const Text('Encrypt data')),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Decrypted data: ', style: Theme.of(context).textTheme.labelLarge),
                      TextSpan(text: _decryptedString, style: Theme.of(context).textTheme.labelLarge),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => _onDecryptedPressed(context), child: const Text('Decrypt data')),
                const Divider(),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => _onDeleteKeyPressed(context), child: const Text('Delete key by tag')),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'TPM version: ', style: Theme.of(context).textTheme.labelLarge),
                      if (_tpmVersion != null)
                        TextSpan(
                          text: '$_tpmVersion',
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => _onVersionCheckPressed(context), child: const Text('Check TPM version')),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'TPM keys (${_tpmKeys.length}): ', style: Theme.of(context).textTheme.labelLarge),
                      TextSpan(
                        text: _tpmKeys.map((key) => key.name).join(', '),
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(onPressed: () => _onListKeysPressed(context), child: const Text('List TPM keys')),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Universally encrypted data: ', style: Theme.of(context).textTheme.labelLarge),
                      TextSpan(
                        text: _universalEncryptedString,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _onUniversalEncryptPressed(context),
                  child: const Text('Universal encrypt'),
                ),
                const Divider(),
                RichText(
                  text: TextSpan(
                    children: [
                      TextSpan(text: 'Universally decrypted data: ', style: Theme.of(context).textTheme.labelLarge),
                      TextSpan(
                        text: _universalDecryptedString,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => _onUniversalDecryptPressed(context),
                  child: const Text('Universal decrypt'),
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

  Future<void> _onSECheckPressed(BuildContext context) async {
    try {
      final status = await _biometricCipherPlugin.getTPMStatus();
      final isSupported = status == TPMStatus.supported;

      setState(() => _secureEnclaveAvailable = isSupported);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check SE error: $e')));
      }
    }
  }

  Future<void> _onBiometricCheckPressed(BuildContext context) async {
    try {
      final status = await _biometricCipherPlugin.getBiometryStatus();
      final isSupported = status == BiometricStatus.supported;

      setState(() => _biometricAvailable = isSupported);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check biometric error: $e')));
      }
    }
  }

  Future<void> _onGenerateKeyPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tag for key generation')));

      return;
    }

    {
      try {
        await _biometricCipherPlugin.generateKey(tag: _tagTextController.text);
        setState(() => _isKeyGenerated = true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Generation key error: $e')));
        }
      }
    }
  }

  Future<void> _onEncryptedPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tag for key encryption')));

      return;
    }

    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter data for encryption')));

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
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Encryption error: $e')));
      }
    }
  }

  Future<void> _onDecryptedPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tag for key decryption')));

      return;
    }

    if (_encryptedString.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Decryption data is empty!!! Encrypt data before decryption')));

      return;
    }

    try {
      final decryptedString = await _biometricCipherPlugin.decrypt(tag: tag, data: _encryptedString);

      setState(() => _decryptedString = decryptedString ?? '');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Decryption error: $e')));
      }
    }
  }

  Future<void> _onDeleteKeyPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tag for key deletion')));

      return;
    }

    try {
      await _biometricCipherPlugin.deleteKey(tag: _tagTextController.text);

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Key was deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Deletion key error: $e')));
      }
    }
  }

  Future<void> _onVersionCheckPressed(BuildContext context) async {
    try {
      final version = await _biometricCipherPlugin.getTpmVersion();

      setState(() => _tpmVersion = version);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Check TPM version error: $e')));
      }
    }
  }

  Future<void> _onListKeysPressed(BuildContext context) async {
    try {
      final keys = await _biometricCipherPlugin.listKeys();

      setState(() => _tpmKeys = keys);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('List TPM keys error: $e')));
      }
    }
  }

  Future<void> _onUniversalEncryptPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tag for universal encryption')));

      return;
    }

    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter data for universal encryption')));

      return;
    }

    try {
      final encryptedString = await _biometricCipherPlugin.encryptString(
        tag: _tagTextController.text,
        data: _textController.text,
      );

      setState(() => _universalEncryptedString = encryptedString);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Universal encryption error: $e')));
      }
    }
  }

  Future<void> _onUniversalDecryptPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter tag for universal decryption')));

      return;
    }

    if (_universalEncryptedString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Universal encryption data is empty! Universal encrypt data before decryption')),
      );

      return;
    }

    try {
      final decryptedString = await _biometricCipherPlugin.decryptString(
        tag: _tagTextController.text,
        data: _universalEncryptedString,
      );

      setState(() => _universalDecryptedString = decryptedString);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Universal decryption error: $e')));
      }
    }
  }
}
