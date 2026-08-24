import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/config/public_config.dart';

void main() {
  PublicConfig configured({
    Uri? api,
    String publishableKey = 'sb_publishable_example',
    String releaseEnvironment = 'test',
  }) => PublicConfig(
    apiBaseUri: api ?? Uri.parse('https://api.hhm.example'),
    sharedAuthIssuer: Uri.parse('https://auth.hhm.example'),
    supabaseUri: Uri.parse('https://project.supabase.co'),
    supabasePublishableKey: publishableKey,
    otelEndpoint: Uri.parse('https://telemetry.hhm.example/v1/traces'),
    releaseEnvironment: releaseEnvironment,
  );

  test('accepts HTTPS public configuration', () {
    expect(configured().isConfigured, isTrue);
  });

  test('permits HTTP only for loopback development', () {
    expect(
      configured(api: Uri.parse('http://127.0.0.1:8080')).apiBaseUri.port,
      8080,
    );
    expect(
      () => configured(api: Uri.parse('http://api.hhm.example')),
      throwsFormatException,
    );
  });

  test('rejects non-public Supabase credentials', () {
    expect(
      () => configured(publishableKey: 'sb_secret_not_for_apps'),
      throwsFormatException,
    );
    expect(
      () => configured(publishableKey: 'service_role_not_for_apps'),
      throwsFormatException,
    );
  });

  test('diagnostic string does not disclose endpoints or keys', () {
    final config = configured();
    expect(config.toString(), contains('configured: true'));
    expect(config.toString(), isNot(contains(config.supabasePublishableKey)));
    expect(config.toString(), isNot(contains(config.apiBaseUri.host)));
  });

  test('rejects arbitrary identifying release labels', () {
    expect(
      () => configured(releaseEnvironment: 'alex-personal-build'),
      throwsFormatException,
    );
  });
}
