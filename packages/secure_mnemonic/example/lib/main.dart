import 'package:flutter/material.dart';
import 'package:secure_mnemonic_example/tpm_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      home: TPMScreen(),
    );
  }
}
