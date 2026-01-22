import 'package:flutter/material.dart';
import 'package:mfa_demo/core/constants/app_constants.dart';
import 'package:mfa_demo/core/extensions/context_extensions.dart';
import 'package:mfa_demo/core/utils/time_format_utils.dart';

Future<Duration?> showTimeoutPickerDialog(
  BuildContext context, {
  required Duration currentSelection,
}) => showDialog<Duration>(
  context: context,
  builder: (context) => TimeoutPickerDialog(
    currentSelection: currentSelection,
  ),
);

class TimeoutPickerDialog extends StatefulWidget {
  final Duration currentSelection;

  const TimeoutPickerDialog({
    super.key,
    required this.currentSelection,
  });

  @override
  State<TimeoutPickerDialog> createState() => _TimeoutPickerDialogState();
}

class _TimeoutPickerDialogState extends State<TimeoutPickerDialog> {
  final _scrollController = ScrollController();
  late Duration _selected;

  List<Duration> get _options => AppConstants.lockTimeoutOptions;

  @override
  void initState() {
    super.initState();
    _selected = _options.contains(widget.currentSelection) ? widget.currentSelection : AppConstants.lockTimeoutDuration;
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Select Auto-Lock Timeout'),
    content: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 320),
      child: Scrollbar(
        controller: _scrollController,
        child: SingleChildScrollView(
          controller: _scrollController,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in _options)
                ListTile(
                  leading: Icon(
                    Icons.schedule,
                    color: option == _selected ? Theme.of(context).colorScheme.primary : null,
                  ),
                  title: Text(
                    TimeFormatUtils.formatLockTimeout(option),
                  ),
                  trailing: option == _selected ? const Icon(Icons.check) : null,
                  onTap: () => setState(() => _selected = option),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: context.pop,
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () => context.pop(result: _selected),
        child: const Text('Save'),
      ),
    ],
  );

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }
}
