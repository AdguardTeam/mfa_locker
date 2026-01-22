import 'dart:async';

import 'package:action_bloc/action_bloc.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locker/storage/models/domain/entry_id.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/features/locker/bloc/locker_bloc.dart';
import 'package:mfa_demo/features/locker/data/models/authentication_result.dart';
import 'package:mfa_demo/features/locker/views/storage/add_entry_screen.dart';
import 'package:mfa_demo/features/locker/views/widgets/authentication_bottom_sheet.dart';
import 'package:mfa_demo/features/locker/views/widgets/confirmation_dialog.dart';
import 'package:mfa_demo/features/locker/views/widgets/confirmation_style.dart';
import 'package:mfa_demo/features/locker/views/widgets/entries_list_view.dart';
import 'package:mfa_demo/features/locker/views/widgets/entry_value_dialog.dart';
import 'package:mfa_demo/features/locker/views/widgets/loading_overlay.dart';
import 'package:mfa_demo/features/locker/views/widgets/locker_bloc_biometric_stream.dart';
import 'package:mfa_demo/features/locker/views/widgets/unlocked_screen_actions.dart';

/// Screen shown when storage is unlocked
class UnlockedScreen extends StatelessWidget {
  const UnlockedScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Storage Unlocked'),
      actions: [
        UnlockedScreenActions(
          onClearAll: () => _clearAllData(context),
        ),
      ],
    ),
    floatingActionButton: FloatingActionButton(
      onPressed: () => context.push(const AddEntryScreen()),
      tooltip: 'Add entry',
      child: const Icon(Icons.add),
    ),
    body: BlocActionListener<LockerBloc, LockerState, LockerAction>(
      listener: (context, action) {
        action.mapOrNull(
          showEntryValue: (value) {
            showDialog<void>(
              context: context,
              builder: (context) => EntryValueDialog(
                entryName: value.name,
                entryValue: value.value,
              ),
            );
          },
        );
      },
      child: BlocBuilder<LockerBloc, LockerState>(
        buildWhen: (previous, current) =>
            previous.entries != current.entries || previous.loadState != current.loadState,
        builder: (context, state) {
          final entries = state.entries;

          return Stack(
            children: [
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      '${entries.length} ${entries.length == 1 ? 'entry' : 'entries'} stored',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: EntriesListView(
                      entries: entries,
                      onDeleteEntry: (entryId, entryName) => _deleteEntry(context, entryId, entryName),
                      onViewEntry: (entryId, entryName) => _viewEntry(context, entryId, entryName),
                    ),
                  ),
                ],
              ),
              if (state.loadState == LoadState.loading) const LoadingOverlay(message: 'Processing...'),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _viewEntry(BuildContext context, EntryId entryId, String entryName) async {
    final bloc = context.read<LockerBloc>();
    final isBiometricEnabled = bloc.state.biometricState.isEnabled;

    final result = await showModalBottomSheet<AuthenticationResult?>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => AuthenticationBottomSheet(
        title: 'Authenticate to view entry',
        showBiometricButton: isBiometricEnabled,
        biometricResultStream: bloc.biometricResultStream,
        onBiometricPressed: isBiometricEnabled
            ? () => bloc.add(
                LockerEvent.readEntryWithBiometricRequested(
                  id: entryId,
                  name: entryName,
                ),
              )
            : null,
      ),
    );

    if (!context.mounted || result == null) {
      return;
    }

    if (result.hasValidPassword) {
      bloc.add(
        LockerEvent.viewEntryRequested(
          id: entryId,
          name: entryName,
          password: result.password!,
        ),
      );
    }
  }

  Future<void> _deleteEntry(BuildContext context, EntryId entryId, String entryName) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Delete Entry',
      content: 'Are you sure you want to delete "$entryName"?',
      confirmText: 'Delete',
    );

    if (!confirmed || !context.mounted) {
      return;
    }

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
                LockerEvent.deleteEntryWithBiometricRequested(
                  id: entryId,
                ),
              )
            : null,
      ),
    );

    if (!context.mounted) {
      return;
    }

    if (result?.isBiometricSuccess == true) {
      return;
    } else if (result.hasValidPassword) {
      bloc.add(
        LockerEvent.deleteEntryRequested(
          id: entryId,
          password: result!.password!,
        ),
      );
    }
  }

  Future<void> _clearAllData(BuildContext context) async {
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Clear All Data',
      content:
          'This will permanently delete ALL entries and reset the storage. '
          'This action cannot be undone.\n\n'
          'Are you sure you want to continue?',
      confirmText: 'Clear All',
      style: ConfirmationStyle.danger,
    );

    if (!confirmed || !context.mounted) {
      return;
    }

    context.read<LockerBloc>().add(const LockerEvent.eraseStorageRequested());
  }
}
