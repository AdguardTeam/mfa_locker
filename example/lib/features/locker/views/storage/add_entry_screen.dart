import 'dart:async';

import 'package:action_bloc/action_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/utils/form_validators.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet.dart';
import 'package:mfa_demo/features/locker/views/widgets/locker_bloc_biometric_stream.dart';

/// Screen for adding a new entry
class AddEntryScreen extends StatefulWidget {
  const AddEntryScreen({super.key});

  @override
  State<AddEntryScreen> createState() => _AddEntryScreenState();
}

class _AddEntryScreenState extends State<AddEntryScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Add Entry'),
    ),
    body: BlocActionListener<LockerBloc, LockerState, LockerAction>(
      listener: (context, action) {
        action.mapOrNull(
          showError: (_) {},
          showSuccess: (_) {},
          navigateBack: (_) {
            if (context.mounted) {
              context.pop();
            }
          },
        );
      },
      child: BlocBuilder<LockerBloc, LockerState>(
        buildWhen: (previous, current) => previous.loadState != current.loadState,
        builder: (context, state) => SingleChildScrollView(
          padding: const EdgeInsets.all(16.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Add a new entry',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Store a new key-value pair in your secure storage',
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Entry Name',
                    border: OutlineInputBorder(),
                    hintText: 'e.g., API Key, Password',
                  ),
                  validator: (value) => FormValidators.required(value, fieldName: 'an entry name'),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _valueController,
                  decoration: const InputDecoration(
                    labelText: 'Entry Value',
                    border: OutlineInputBorder(),
                    hintText: 'The secret value to store',
                  ),
                  maxLines: 3,
                  validator: (value) => FormValidators.required(value, fieldName: 'an entry value'),
                ),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: state.loadState == LoadState.loading ? null : _addEntry,
                  child: state.loadState == LoadState.loading
                      ? const SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                          ),
                        )
                      : const Text('Add Entry'),
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
    _nameController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _addEntry() {
    if (_formKey.currentState!.validate()) {
      _showAuthenticationPrompt();
    }
  }

  Future<void> _showAuthenticationPrompt() async {
    final bloc = context.read<LockerBloc>();

    final result = await showModalBottomSheet<AuthenticationResult?>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => AuthenticationBottomSheet(
        title: 'Unlock Storage',
        showBiometricButton: bloc.state.biometricState.isEnabled,
        biometricResultStream: bloc.biometricResultStream,
        onBiometricPressed: bloc.state.biometricState.isEnabled
            ? () => bloc.add(
                LockerEvent.addEntryWithBiometricRequested(
                  name: _nameController.text,
                  value: _valueController.text,
                ),
              )
            : null,
      ),
    );

    if (!mounted) {
      return;
    }

    if (result.hasValidPassword) {
      bloc.add(
        LockerEvent.addEntryRequested(
          name: _nameController.text,
          value: _valueController.text,
          password: result!.password!,
        ),
      );
    }
  }
}
