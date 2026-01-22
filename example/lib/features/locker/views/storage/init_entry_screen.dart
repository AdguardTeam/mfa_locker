import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/core/utils/time_format_utils.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/views/utils/form_validators.dart';
import 'package:mfa_demo/features/locker/views/widgets/timeout_picker_dialog.dart';

/// Screen for adding the initial entry
class InitEntryScreen extends StatefulWidget {
  const InitEntryScreen({super.key});

  @override
  State<InitEntryScreen> createState() => _InitEntryScreenState();
}

class _InitEntryScreenState extends State<InitEntryScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _valueController = TextEditingController();
  Duration _selectedTimeout = AppConstants.lockTimeoutDuration;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Add First Entry'),
    ),
    body: BlocBuilder<LockerBloc, LockerState>(
      buildWhen: (previous, current) => previous.loadState != current.loadState,
      builder: (context, state) => SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Add your first entry',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Store a key-value pair in your secure storage',
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
              const SizedBox(height: 16),
              Card(
                child: ListTile(
                  leading: const Icon(Icons.timer_outlined),
                  title: const Text('Auto-Lock Timeout'),
                  subtitle: Text(
                    TimeFormatUtils.formatLockTimeout(_selectedTimeout),
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: state.loadState == LoadState.loading ? null : _pickTimeout,
                ),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: state.loadState == LoadState.loading ? null : _submitInitialEntry,
                child: state.loadState == LoadState.loading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                        ),
                      )
                    : const Text('Initialize Storage'),
              ),
            ],
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

  void _submitInitialEntry() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    context.read<LockerBloc>().add(
      LockerEvent.initialEntrySubmitted(
        name: _nameController.text,
        value: _valueController.text,
        lockTimeout: _selectedTimeout,
      ),
    );
  }

  Future<void> _pickTimeout() async {
    final result = await showTimeoutPickerDialog(
      context,
      currentSelection: _selectedTimeout,
    );

    if (result != null && mounted) {
      setState(() {
        _selectedTimeout = result;
      });
    }
  }
}
