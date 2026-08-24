/// Public, compile-time configuration that is safe to expose in an app binary.
///
/// Flutter `--dart-define` values are not secrets: users can recover them from
/// a shipped binary. Service credentials and authenticated telemetry headers
/// must stay behind HHM backend APIs.
final class PublicConfig {
  PublicConfig({
    required this.apiBaseUri,
    required this.sharedAuthIssuer,
    required this.supabaseUri,
    required this.supabasePublishableKey,
    required this.otelEndpoint,
    required this.releaseEnvironment,
  }) {
    _requireTransportUri('HHM_API_BASE_URL', apiBaseUri);
    _requireTransportUri('HHM_SHARED_AUTH_ISSUER', sharedAuthIssuer);
    _requireTransportUri('HHM_SUPABASE_URL', supabaseUri);
    _requireTransportUri('HHM_OTEL_EXPORTER_OTLP_ENDPOINT', otelEndpoint);
    _requirePublicSupabaseKey(supabasePublishableKey);
    _requireReleaseEnvironment(releaseEnvironment);
  }

  factory PublicConfig.fromEnvironment() {
    const api = String.fromEnvironment(
      'HHM_API_BASE_URL',
      defaultValue: 'https://api.hhm.invalid',
    );
    const issuer = String.fromEnvironment(
      'HHM_SHARED_AUTH_ISSUER',
      defaultValue: 'https://auth.hhm.invalid',
    );
    const supabase = String.fromEnvironment(
      'HHM_SUPABASE_URL',
      defaultValue: 'https://supabase.hhm.invalid',
    );
    const supabaseKey = String.fromEnvironment(
      'HHM_SUPABASE_PUBLISHABLE_KEY',
      defaultValue: 'not-configured',
    );
    const otel = String.fromEnvironment(
      'HHM_OTEL_EXPORTER_OTLP_ENDPOINT',
      defaultValue: 'https://telemetry.hhm.invalid/v1/traces',
    );
    const environment = String.fromEnvironment(
      'HHM_RELEASE_ENVIRONMENT',
      defaultValue: 'development',
    );

    return PublicConfig(
      apiBaseUri: _parseUri('HHM_API_BASE_URL', api),
      sharedAuthIssuer: _parseUri('HHM_SHARED_AUTH_ISSUER', issuer),
      supabaseUri: _parseUri('HHM_SUPABASE_URL', supabase),
      supabasePublishableKey: supabaseKey,
      otelEndpoint: _parseUri('HHM_OTEL_EXPORTER_OTLP_ENDPOINT', otel),
      releaseEnvironment: environment,
    );
  }

  final Uri apiBaseUri;
  final Uri sharedAuthIssuer;
  final Uri supabaseUri;
  final String supabasePublishableKey;
  final Uri otelEndpoint;
  final String releaseEnvironment;

  bool get isConfigured =>
      !apiBaseUri.host.endsWith('.invalid') &&
      !sharedAuthIssuer.host.endsWith('.invalid') &&
      !supabaseUri.host.endsWith('.invalid') &&
      supabasePublishableKey != 'not-configured';

  static Uri _parseUri(String name, String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty) {
      throw FormatException('$name must be an absolute URI');
    }
    return uri;
  }

  static void _requireTransportUri(String name, Uri uri) {
    final isLoopback =
        uri.host == 'localhost' || uri.host == '127.0.0.1' || uri.host == '::1';
    final isSecure = uri.scheme == 'https';
    final isLocalDevelopment = uri.scheme == 'http' && isLoopback;
    if ((!isSecure && !isLocalDevelopment) || uri.userInfo.isNotEmpty) {
      throw FormatException(
        '$name must use HTTPS (HTTP is permitted only for a loopback host) '
        'and must not contain credentials',
      );
    }
  }

  static void _requirePublicSupabaseKey(String value) {
    final normalized = value.toLowerCase();
    if (normalized.contains('service_role') ||
        normalized.startsWith('sb_secret_') ||
        normalized.contains('private')) {
      throw const FormatException(
        'HHM_SUPABASE_PUBLISHABLE_KEY must be a public publishable key',
      );
    }
  }

  static void _requireReleaseEnvironment(String value) {
    const allowed = <String>{'development', 'test', 'staging', 'production'};
    if (!allowed.contains(value)) {
      throw const FormatException(
        'HHM_RELEASE_ENVIRONMENT must be a known non-identifying label',
      );
    }
  }

  @override
  String toString() =>
      'PublicConfig(environment: $releaseEnvironment, configured: $isConfigured)';
}
