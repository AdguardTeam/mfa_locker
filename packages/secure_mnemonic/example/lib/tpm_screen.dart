import 'package:flutter/material.dart';
import 'package:secure_mnemonic/data/biometric_status.dart';
import 'package:secure_mnemonic/data/model/android_config.dart';
import 'package:secure_mnemonic/data/model/config_data.dart';
import 'package:secure_mnemonic/data/tpm_status.dart';
import 'package:secure_mnemonic/secure_mnemonic.dart';

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

  late final SecureMnemonic _secureMnemonicPlugin;
  late final TextEditingController _textController;
  late final TextEditingController _tagTextController;

  @override
  void initState() {
    super.initState();

    _secureMnemonicPlugin = SecureMnemonic();
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

    _secureMnemonicPlugin.configure(config: config);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('Plugin example app'),
        ),
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
                          TextSpan(
                            text: 'Secure Enclave availability: ',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
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
                          TextSpan(
                            text: 'Biometric availability: ',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
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
                            TextSpan(
                              text: 'Key is generated',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          if (!_isKeyGenerated) ...[
                            TextSpan(
                              text: 'Key is ',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                            TextSpan(
                              text: 'NOT',
                              style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.red),
                            ),
                            TextSpan(
                              text: ' generated',
                              style: Theme.of(context).textTheme.labelLarge,
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _tagTextController,
                      decoration: const InputDecoration(
                        labelText: 'Tag for key generation',
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => _onGenerateKeyPressed(context),
                      child: const Text('Generate key'),
                    ),
                    const Divider(),
                    TextField(
                      controller: _textController,
                      decoration: const InputDecoration(
                        label: Text('Enter data to encrypt'),
                      ),
                    ),
                    const SizedBox(height: 20),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Encrypted data: ',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          TextSpan(
                            text: _encryptedString,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => _onEncryptedPressed(context),
                      child: const Text('Encrypt data'),
                    ),
                    const Divider(),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'Decrypted data: ',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          TextSpan(
                            text: _decryptedString,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => _onDecryptedPressed(context),
                      child: const Text('Decrypt data'),
                    ),
                    const Divider(),
                    const SizedBox(height: 20),
                    FilledButton(
                      onPressed: () => _onDeleteKeyPressed(context),
                      child: const Text('Delete key by tag'),
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
      final status = await _secureMnemonicPlugin.getTPMStatus();
      final isSupported = status == TPMStatus.supported;

      setState(() => _secureEnclaveAvailable = isSupported);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Check SE error: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _onBiometricCheckPressed(BuildContext context) async {
    try {
      final status = await _secureMnemonicPlugin.getBiometryStatus();
      final isSupported = status == BiometricStatus.supported;

      setState(() => _biometricAvailable = isSupported);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Check biometric error: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _onGenerateKeyPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter tag for key generation',
          ),
        ),
      );

      return;
    }

    {
      try {
        await _secureMnemonicPlugin.generateKey(tag: _tagTextController.text);
        setState(() => _isKeyGenerated = true);
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Generation key error: $e',
              ),
            ),
          );
        }
      }
    }
  }

  Future<void> _onEncryptedPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter tag for key encryption',
          ),
        ),
      );

      return;
    }

    if (_textController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter data for encryption',
          ),
        ),
      );

      return;
    }

    try {
      final encryptedString = await _secureMnemonicPlugin.encrypt(
        tag: _tagTextController.text,
        data: _textController.text,
      );

      setState(() => _encryptedString = encryptedString ?? '');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Encryption error: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _onDecryptedPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter tag for key decryption',
          ),
        ),
      );

      return;
    }

    if (_encryptedString.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Decryption data is empty!!! Encrypt data before decryption',
          ),
        ),
      );

      return;
    }

    try {
      final decryptedString = await _secureMnemonicPlugin.decrypt(
        tag: tag,
        data: _encryptedString,
      );

      setState(() => _decryptedString = decryptedString ?? '');
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Decryption error: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _onDeleteKeyPressed(BuildContext context) async {
    if (_tagTextController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Enter tag for key deletion',
          ),
        ),
      );

      return;
    }

    try {
      await _secureMnemonicPlugin.deleteKey(
        tag: _tagTextController.text,
      );

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Key was deleted',
            ),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Deletion key error: $e',
            ),
          ),
        );
      }
    }
  }
}
