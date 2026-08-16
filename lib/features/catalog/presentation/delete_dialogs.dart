/// The two delete confirmations (owner's request: "the option to delete
/// each item, and also the option to delete all items").
///
/// Delete is safe by construction in the service — an item with event
/// history is archived under the hood (it leaves every list; history stays
/// for forecasting), one without is truly removed — so the dialogs promise
/// only what every case shares: the item comes off the list, past events
/// stay in the history. The UI never distinguishes the cases.
///
/// Color restraint (spec §2): destructive red goes on the CONFIRMING
/// button alone — the same FilledButton error/onError treatment the
/// workspace-reset and restore screens use — never on the menu entry that
/// opened the dialog.
library;

import 'package:flutter/material.dart';

/// Opens the per-item confirmation. Resolves true when the owner confirmed.
Future<bool> confirmDeleteItem(
  BuildContext context, {
  required String itemName,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete "$itemName"?'),
      content: const Text(
        'It comes off your items list. What happened at past events stays '
        'in your history.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        _DestructiveButton(
          label: 'Delete',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Opens the delete-all confirmation over the current live [itemCount].
/// Resolves true when the owner confirmed.
Future<bool> confirmDeleteAllItems(
  BuildContext context, {
  required int itemCount,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Delete all items?'),
      content: Text(
        'Your whole items list is cleared '
        '($itemCount item${itemCount == 1 ? '' : 's'}). '
        'What happened at past events stays in your history.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        _DestructiveButton(
          label: 'Delete all',
          onPressed: () => Navigator.of(context).pop(true),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The confirming action, and only it, wears the theme's error pair.
class _DestructiveButton extends StatelessWidget {
  const _DestructiveButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.error,
        foregroundColor: scheme.onError,
      ),
      onPressed: onPressed,
      child: Text(label),
    );
  }
}
