import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Hands a downloaded build to Android's package installer (ADR 0026).
///
/// The app never installs anything itself. The installer shows its own
/// confirmation and refuses any package not signed with the key that signed the
/// installed app — that check, not ours, is what makes this safe.
abstract interface class AppUpdateInstaller {
  /// Whether this app may ask the system to install a package at all. On
  /// Android this is a per-app setting the user grants once.
  Future<bool> canInstall();

  /// Opens the system screen where that permission is granted.
  Future<bool> openPermissionSettings();

  /// Where a download should land: inside the app's own cache, which is the
  /// only directory the file provider exposes.
  Future<Directory> downloadDirectory();

  /// Verifies the file against the digest the manifest published.
  ///
  /// This catches a truncated or corrupted download. It is not the security
  /// boundary: a file that hashes correctly but is signed with another key is
  /// still refused by the installer.
  Future<bool> matchesDigest({required File file, required String sha256});

  Future<void> install(File package);
}

class AppUpdateInstallFailed implements Exception {
  const AppUpdateInstallFailed();
}

class PlatformAppUpdateInstaller implements AppUpdateInstaller {
  const PlatformAppUpdateInstaller();

  static const MethodChannel _channel = MethodChannel(
    'com.mobilefinanceassistant/update_installer',
  );

  @override
  Future<bool> canInstall() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('canInstall') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<bool> openPermissionSettings() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>(
            'openInstallPermissionSettings',
          ) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  @override
  Future<Directory> downloadDirectory() async {
    final cache = await getTemporaryDirectory();
    final updates = Directory('${cache.path}/updates');
    if (!updates.existsSync()) {
      await updates.create(recursive: true);
    }
    return updates;
  }

  @override
  Future<bool> matchesDigest({
    required File file,
    required String sha256,
  }) async {
    // Streamed: the file is tens of megabytes and there is no reason to hold
    // it in memory to hash it.
    final sink = Sha256().newHashSink();
    await for (final chunk in file.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final digest = await sink.hash();
    final actual = digest.bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return actual == sha256;
  }

  @override
  Future<void> install(File package) async {
    try {
      await _channel.invokeMethod<void>('install', <String, Object?>{
        'path': package.path,
      });
    } on PlatformException {
      throw const AppUpdateInstallFailed();
    } on MissingPluginException {
      throw const AppUpdateInstallFailed();
    }
  }
}

/// Replaceable so a test can drive the flow without an Android installer.
final appUpdateInstallerProvider = Provider<AppUpdateInstaller>(
  (ref) => const PlatformAppUpdateInstaller(),
);
