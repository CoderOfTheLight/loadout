/// The two small folder dialogs — create ("New folder…") and rename — both
/// writing through `CatalogService` (single command path; no direct DB
/// writes from screens).
///
/// The create dialog asks for exactly what a folder is: a name, and its
/// default answer to the one question. The rename dialog asks for the name
/// alone. Validation mirrors the command validator (1–60 characters,
/// unique among live folders) so the honest error shows up inline instead
/// of as a snackbar.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/providers.dart';
import '../../../app/theme.dart';
import '../../../core/result.dart';
import '../domain/demand_basis.dart';
import 'demand_basis_choice.dart';

/// Mirrors the command validator's folder-name rule (1–60 characters).
String? validateFolderName(String? text) {
  final name = (text ?? '').trim();
  if (name.isEmpty) {
    return 'Enter a name';
  }
  if (name.length > 60) {
    return 'Keep the name under 60 characters';
  }
  return null;
}

/// Opens the "New folder" dialog. Resolves to the created folderId, or null
/// when the owner cancelled.
Future<String?> showCreateFolderDialog(BuildContext context) =>
    showDialog<String>(
      context: context,
      builder: (_) => const _CreateFolderDialog(),
    );

/// Opens the rename dialog for [folderId]. Resolves to true when a rename
/// was saved.
Future<bool?> showRenameFolderDialog(
  BuildContext context, {
  required String folderId,
  required String currentName,
}) => showDialog<bool>(
  context: context,
  builder: (_) =>
      _RenameFolderDialog(folderId: folderId, currentName: currentName),
);

class _CreateFolderDialog extends ConsumerStatefulWidget {
  const _CreateFolderDialog();

  @override
  ConsumerState<_CreateFolderDialog> createState() =>
      _CreateFolderDialogState();
}

class _CreateFolderDialogState extends ConsumerState<_CreateFolderDialog> {
  final _name = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  DemandBasis _basis = DemandBasis.perPerson;
  bool _submitting = false;
  String? _serviceError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() => _serviceError = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    final result = await ref
        .read(catalogServiceProvider)
        .createFolder(name: _name.text.trim(), demandBasis: _basis);
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok(:final value):
        Navigator.of(context).pop(value);
      case Err(:final error):
        setState(() {
          _submitting = false;
          _serviceError = error.message.contains('already exists')
              ? 'A folder with this name already exists.'
              : "Couldn't add the folder. Try again.";
        });
        _formKey.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('New folder'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _name,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Folder name',
                  hintText: 'Sales table',
                  border: OutlineInputBorder(),
                ),
                onChanged: (_) {
                  if (_serviceError != null) {
                    setState(() => _serviceError = null);
                  }
                },
                onFieldSubmitted: (_) => _submit(),
                validator: (text) => _serviceError ?? validateFolderName(text),
              ),
              const SizedBox(height: Space.l),
              Text(
                'Does how much you bring depend on how many people come?',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: Space.s),
              Text(
                'New items filed here start with this answer. Any single '
                'item can differ.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: Space.m),
              DemandBasisChoice(
                value: _basis,
                onChanged: (basis) => setState(() => _basis = basis),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: const Text('Add folder'),
        ),
      ],
    );
  }
}

class _RenameFolderDialog extends ConsumerStatefulWidget {
  const _RenameFolderDialog({
    required this.folderId,
    required this.currentName,
  });

  final String folderId;
  final String currentName;

  @override
  ConsumerState<_RenameFolderDialog> createState() =>
      _RenameFolderDialogState();
}

class _RenameFolderDialogState extends ConsumerState<_RenameFolderDialog> {
  late final _name = TextEditingController(text: widget.currentName);
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  String? _serviceError;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    setState(() => _serviceError = null);
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _submitting = true);
    final result = await ref
        .read(catalogServiceProvider)
        .renameFolder(folderId: widget.folderId, name: _name.text.trim());
    if (!mounted) {
      return;
    }
    switch (result) {
      case Ok():
        Navigator.of(context).pop(true);
      case Err(:final error):
        setState(() {
          _submitting = false;
          _serviceError = error.message.contains('already exists')
              ? 'A folder with this name already exists.'
              : "Couldn't rename the folder. Try again.";
        });
        _formKey.currentState!.validate();
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Rename folder'),
    content: Form(
      key: _formKey,
      child: TextFormField(
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        decoration: const InputDecoration(
          labelText: 'Folder name',
          border: OutlineInputBorder(),
        ),
        onChanged: (_) {
          if (_serviceError != null) {
            setState(() => _serviceError = null);
          }
        },
        onFieldSubmitted: (_) => _submit(),
        validator: (text) => _serviceError ?? validateFolderName(text),
      ),
    ),
    actions: [
      TextButton(
        onPressed: _submitting ? null : () => Navigator.of(context).pop(),
        child: const Text('Cancel'),
      ),
      FilledButton(
        onPressed: _submitting ? null : _submit,
        child: const Text('Rename'),
      ),
    ],
  );
}
