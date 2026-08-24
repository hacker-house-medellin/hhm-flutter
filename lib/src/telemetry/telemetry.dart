enum HhmOperation {
  appStarted,
  authStarted,
  authCompleted,
  visitorQrFetched,
  visitorQrRedeemed,
  presenceChallengeRequested,
  presenceEvidenceSubmitted,
  peerSelectionStarted,
  peerHandshakeCompleted,
  peerEnvelopeRejected,
  peerUpdateManifestChecked,
}

enum HhmOperationResult { succeeded, rejected, cancelled, unavailable }

enum DurationBucket { under100ms, under1s, under5s, fiveSecondsOrMore }

enum HhmPlatform { android, ios, linux, macos, windows, web }

enum HhmReleaseEnvironment { development, test, staging, production }

/// A deliberately closed telemetry schema.
///
/// It has no arbitrary attribute map, identifiers, free-form error text, QR
/// data, location, radio identifiers, authorization material, or user content.
/// That makes the privacy boundary auditable before the event reaches Ores OTEL.
final class SafeTelemetryEvent {
  const SafeTelemetryEvent({
    required this.operation,
    required this.result,
    required this.platform,
    required this.releaseEnvironment,
    required this.duration,
  });

  final HhmOperation operation;
  final HhmOperationResult result;
  final HhmPlatform platform;
  final HhmReleaseEnvironment releaseEnvironment;
  final DurationBucket duration;

  Map<String, String> toOtelAttributes() => <String, String>{
    'hhm.operation': operation.name,
    'hhm.result': result.name,
    'hhm.platform': platform.name,
    'deployment.environment': releaseEnvironment.name,
    'hhm.duration_bucket': duration.name,
  };
}

/// Low-level exporter implemented by a reviewed Ores OTEL / OTLP adapter.
///
/// Mobile and browser clients send only [SafeTelemetryEvent] to the configured
/// HHM collector. Authentication headers are provisioned at runtime by the
/// platform transport and are never compile-time configuration.
abstract interface class TelemetrySink {
  Future<void> emit(SafeTelemetryEvent event);
}

final class OresTelemetry {
  const OresTelemetry(this._sink);

  final TelemetrySink _sink;

  Future<void> record(SafeTelemetryEvent event) => _sink.emit(event);

  static DurationBucket bucket(Duration duration) {
    if (duration < const Duration(milliseconds: 100)) {
      return DurationBucket.under100ms;
    }
    if (duration < const Duration(seconds: 1)) {
      return DurationBucket.under1s;
    }
    if (duration < const Duration(seconds: 5)) {
      return DurationBucket.under5s;
    }
    return DurationBucket.fiveSecondsOrMore;
  }
}
