import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/telemetry/telemetry.dart';

void main() {
  test('exports only the closed privacy-safe attribute set', () {
    const event = SafeTelemetryEvent(
      operation: HhmOperation.visitorQrRedeemed,
      result: HhmOperationResult.rejected,
      platform: HhmPlatform.android,
      releaseEnvironment: HhmReleaseEnvironment.test,
      duration: DurationBucket.under1s,
    );
    final attributes = event.toOtelAttributes();

    expect(attributes.keys, <String>{
      'hhm.operation',
      'hhm.result',
      'hhm.platform',
      'deployment.environment',
      'hhm.duration_bucket',
    });
    expect(attributes.keys.any((key) => key.contains('user')), isFalse);
    expect(attributes.keys.any((key) => key.contains('token')), isFalse);
    expect(attributes.keys.any((key) => key.contains('location')), isFalse);
  });

  test('buckets duration without emitting exact timing', () {
    expect(
      OresTelemetry.bucket(const Duration(milliseconds: 99)),
      DurationBucket.under100ms,
    );
    expect(
      OresTelemetry.bucket(const Duration(seconds: 5)),
      DurationBucket.fiveSecondsOrMore,
    );
  });
}
