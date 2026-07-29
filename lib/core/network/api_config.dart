const _primaryApiBaseUrl = String.fromEnvironment('API_BASE_URL');
const _legacyHomeApiBaseUrl = String.fromEnvironment('HOME_API_BASE_URL');
const configuredHomeApiTimezone = String.fromEnvironment(
  'HOME_API_TIMEZONE',
  defaultValue: 'Europe/Berlin',
);

/// Shared backend location for authentication and financial API clients.
///
/// `HOME_API_BASE_URL` remains a fallback so existing Home development and E2E
/// commands keep working while builds migrate to the product-wide name.
String get configuredApiBaseUrl {
  final primary = _primaryApiBaseUrl.trim();
  return primary.isNotEmpty ? primary : _legacyHomeApiBaseUrl.trim();
}

bool get isNetworkBackendConfigured => configuredApiBaseUrl.isNotEmpty;
