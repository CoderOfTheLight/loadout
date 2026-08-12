/// Feature-local seam over `flutter_file_dialog` (design §8.1, §12.19):
/// save-file-only egress and pick-file ingress — no share sheet. Screens
/// resolve this through [fileGatewayProvider]; widget tests override the
/// provider with a fake because platform channels do not exist in host
/// tests. This is the ONLY place the plugin is touched.
library;

import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

abstract interface class FileGateway {
  /// Save-file dialog (SAF `ACTION_CREATE_DOCUMENT` / `UIDocumentPicker`
  /// export). Returns the saved location, or null when the user cancelled.
  Future<String?> saveFile({
    required String sourcePath,
    required String suggestedName,
  });

  /// Pick-file dialog. Returns a readable local path to (a copy of) the
  /// picked file, or null when the user cancelled.
  Future<String?> pickFile();
}

/// Production implementation over the platform dialogs.
final class DialogFileGateway implements FileGateway {
  const DialogFileGateway();

  @override
  Future<String?> saveFile({
    required String sourcePath,
    required String suggestedName,
  }) => FlutterFileDialog.saveFile(
    params: SaveFileDialogParams(
      sourceFilePath: sourcePath,
      fileName: suggestedName,
    ),
  );

  @override
  Future<String?> pickFile() => FlutterFileDialog.pickFile(
    params: const OpenFileDialogParams(
      dialogType: OpenFileDialogType.document,
      copyFileToCacheDir: true,
    ),
  );
}

/// The seam widget tests override with a fake.
final fileGatewayProvider = Provider<FileGateway>(
  (_) => const DialogFileGateway(),
);
