/// Minimal authenticated-session projection available to the Home data layer.
///
/// Home deliberately cannot access refresh credentials or derive an account
/// identity from the bearer token. The authentication feature owns the full
/// secure record and token rotation.
final class HomeSessionSnapshot {
  HomeSessionSnapshot({
    required String accessToken,
    required String cacheScopeId,
    required String revision,
  }) : accessToken =
           _validToken(accessToken) ??
           (throw const FormatException('Invalid access token.')),
       cacheScopeId =
           _validScope(cacheScopeId) ??
           (throw const FormatException('Invalid cache scope.')),
       revision =
           _validRevision(revision) ??
           (throw const FormatException('Invalid session revision.'));

  final String accessToken;
  final String cacheScopeId;
  final String revision;

  String get scopedCacheScopeId => '$cacheScopeId.$revision';

  bool isSameSession(HomeSessionSnapshot? other) {
    return other != null &&
        other.accessToken == accessToken &&
        other.cacheScopeId == cacheScopeId &&
        other.revision == revision;
  }
}

abstract interface class HomeSessionStore {
  Future<HomeSessionSnapshot?> readSession();

  Future<void> clearSession();
}

String? validSessionToken(String value) {
  final result = value.trim();
  if (result.isEmpty ||
      result.length > 8192 ||
      result.codeUnits.any((unit) => unit < 0x20 || unit == 0x7f)) {
    return null;
  }
  return result;
}

String? validCacheScopeId(String value) {
  final result = value.trim();
  return RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(result) ? result : null;
}

String? validSessionRevision(String value) {
  final result = value.trim();
  return RegExp(r'^[a-f0-9]{32}$').hasMatch(result) ? result : null;
}

String? _validToken(String value) => validSessionToken(value);

String? _validScope(String value) => validCacheScopeId(value);

String? _validRevision(String value) => validSessionRevision(value);
