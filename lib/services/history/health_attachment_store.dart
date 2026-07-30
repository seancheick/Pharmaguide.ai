import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

class ImportedHealthAttachment {
  const ImportedHealthAttachment({
    required this.path,
    required this.displayName,
    this.mimeType,
  });

  final String path;
  final String displayName;
  final String? mimeType;
}

typedef HealthAttachmentRoot = Future<Directory> Function();

/// Private, app-sandboxed storage for user-selected Health History files.
///
/// The picker path is never persisted: the selected file is copied into
/// Application Support under an opaque UUID. Nothing is uploaded.
class HealthAttachmentStore {
  HealthAttachmentStore({HealthAttachmentRoot? root})
    : _root = root ?? _defaultRoot;

  static const _directoryName = 'health_history_attachments';
  final HealthAttachmentRoot _root;

  static Future<Directory> _defaultRoot() async {
    final support = await getApplicationSupportDirectory();
    return Directory(path.join(support.path, _directoryName));
  }

  Future<ImportedHealthAttachment> importImage(XFile selected) async {
    final source = File(selected.path);
    if (!await source.exists()) {
      throw const FileSystemException('Selected attachment no longer exists.');
    }
    final root = await _root();
    await root.create(recursive: true);
    final extension = _safeImageExtension(path.extension(selected.name));
    final destination = File(
      path.join(root.path, '${const Uuid().v4()}$extension'),
    );
    await source.copy(destination.path);
    return ImportedHealthAttachment(
      path: destination.path,
      displayName: path.basename(selected.name),
      mimeType: selected.mimeType ?? _mimeFor(extension),
    );
  }

  Future<void> delete(String attachmentPath) async {
    final root = await _root();
    final candidate = File(attachmentPath);
    if (!path.isWithin(root.path, candidate.path)) {
      throw const FileSystemException(
        'Refusing to delete a file outside Health History storage.',
      );
    }
    if (await candidate.exists()) await candidate.delete();
  }

  Future<void> clearAll() async {
    final root = await _root();
    if (await root.exists()) await root.delete(recursive: true);
  }

  static String _safeImageExtension(String raw) {
    final normalized = raw.toLowerCase();
    return const {
          '.jpg',
          '.jpeg',
          '.png',
          '.heic',
          '.webp',
        }.contains(normalized)
        ? normalized
        : '.jpg';
  }

  static String _mimeFor(String extension) => switch (extension) {
    '.png' => 'image/png',
    '.heic' => 'image/heic',
    '.webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}
