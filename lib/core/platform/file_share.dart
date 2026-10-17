import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Hands files the app has written to Android's share sheet (ADR 0030).
///
/// The person chooses where they go — a messenger, a drive, mail, the Files
/// app — and nothing is sent anywhere by the app itself. Reached through a
/// method channel rather than a package, like the update installer: a
/// third-party plugin standing between someone's whole financial record and
/// the system is trust with no return.
abstract interface class FileShare {
  /// An empty directory to write the files into, inside the app's own cache.
  ///
  /// Emptied on every call, so a copy of the record never outlives the next
  /// export. It is not emptied after sharing: the app that receives the files
  /// reads them on its own schedule, and pulling them out from under it is how
  /// the update installer once failed (issue 0010).
  Future<Directory> freshExportDirectory();

  /// Removes whatever an earlier export left behind.
  Future<void> clearExports();

  Future<void> share(List<File> files);
}

class FileShareFailed implements Exception {
  const FileShareFailed();
}

class PlatformFileShare implements FileShare {
  const PlatformFileShare();

  static const MethodChannel _channel = MethodChannel(
    'com.mobilefinanceassistant/file_share',
  );

  Future<Directory> _exports() async {
    final cache = await getTemporaryDirectory();
    return Directory('${cache.path}/exports');
  }

  @override
  Future<Directory> freshExportDirectory() async {
    final exports = await _exports();
    if (exports.existsSync()) await exports.delete(recursive: true);
    await exports.create(recursive: true);
    return exports;
  }

  @override
  Future<void> clearExports() async {
    final exports = await _exports();
    if (exports.existsSync()) await exports.delete(recursive: true);
  }

  @override
  Future<void> share(List<File> files) async {
    if (!Platform.isAndroid) throw const FileShareFailed();
    try {
      await _channel.invokeMethod<void>('share', <String, Object?>{
        'paths': [for (final file in files) file.path],
      });
    } on PlatformException {
      throw const FileShareFailed();
    } on MissingPluginException {
      throw const FileShareFailed();
    }
  }
}

/// Replaceable so a test can export without an Android share sheet.
final fileShareProvider = Provider<FileShare>(
  (ref) => const PlatformFileShare(),
);
