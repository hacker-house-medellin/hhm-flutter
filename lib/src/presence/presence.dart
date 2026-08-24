enum PresenceTransition { signIn, signOut }

enum PresenceSignal {
  bleDoorBeacon,
  platformNearby,
  ultraWideband,
  geofence,
  userConfirmation,
}

/// Explicit resident choice for proximity-assisted presence transitions.
final class ProximityConsent {
  ProximityConsent({
    required this.enabled,
    required this.automaticTransitions,
    required this.grantedAt,
    required Iterable<String> allowedDoorIds,
  }) : allowedDoorIds = Set.unmodifiable(allowedDoorIds);

  final bool enabled;
  final bool automaticTransitions;
  final DateTime grantedAt;
  final Set<String> allowedDoorIds;

  bool permits({required String doorId, required bool automatic}) =>
      enabled &&
      allowedDoorIds.contains(doorId) &&
      (!automatic || automaticTransitions);
}

/// Short-lived, one-use server challenge. It binds evidence to a transition,
/// door, device session, and narrow time window so captured radio observations
/// cannot be replayed later.
final class PresenceChallenge {
  PresenceChallenge({
    required this.challengeId,
    required this.nonce,
    required this.doorId,
    required this.transition,
    required this.issuedAt,
    required this.expiresAt,
  }) {
    if (challengeId.isEmpty || nonce.length < 16 || doorId.isEmpty) {
      throw const FormatException('Presence challenge metadata is incomplete');
    }
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero || lifetime > const Duration(seconds: 30)) {
      throw const FormatException(
        'Presence challenges must expire within 30 seconds',
      );
    }
  }

  final String challengeId;
  final String nonce;
  final String doorId;
  final PresenceTransition transition;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isUsableAt(DateTime now) =>
      !now.isBefore(issuedAt) && now.isBefore(expiresAt);
}

/// Corroborated proximity evidence. Radio identifiers and precise coordinates
/// are intentionally absent from the portable domain object.
final class PresenceEvidence {
  PresenceEvidence({
    required this.challengeId,
    required this.challengeNonce,
    required this.observationNonce,
    required this.observedAt,
    required Iterable<PresenceSignal> signals,
  }) : signals = Set.unmodifiable(signals) {
    if (challengeId.isEmpty ||
        challengeNonce.length < 16 ||
        observationNonce.length < 16) {
      throw const FormatException('Presence evidence nonces are incomplete');
    }
  }

  final String challengeId;
  final String challengeNonce;
  final String observationNonce;
  final DateTime observedAt;
  final Set<PresenceSignal> signals;

  @override
  String toString() =>
      'PresenceEvidence(signals: ${signals.length}, identifiers: [redacted])';
}

/// Local fail-closed preflight. The backend repeats these checks, verifies the
/// signed device/session binding, rate-limits attempts, and consumes the nonce.
final class PresencePolicy {
  const PresencePolicy({
    this.minimumIndependentSignals = 2,
    this.maximumObservationAge = const Duration(seconds: 10),
  });

  final int minimumIndependentSignals;
  final Duration maximumObservationAge;

  bool permitsSubmission({
    required ProximityConsent consent,
    required PresenceChallenge challenge,
    required PresenceEvidence evidence,
    required DateTime now,
    required bool automatic,
  }) {
    if (!consent.permits(doorId: challenge.doorId, automatic: automatic) ||
        !challenge.isUsableAt(now) ||
        evidence.challengeId != challenge.challengeId ||
        evidence.challengeNonce != challenge.nonce ||
        evidence.observedAt.isBefore(challenge.issuedAt) ||
        evidence.observedAt.isAfter(now) ||
        now.difference(evidence.observedAt) > maximumObservationAge ||
        !evidence.signals.contains(PresenceSignal.bleDoorBeacon) ||
        evidence.signals.length < minimumIndependentSignals) {
      return false;
    }

    if (automatic) {
      final corroboratedByEnvironment = evidence.signals.any(
        (signal) =>
            signal == PresenceSignal.platformNearby ||
            signal == PresenceSignal.ultraWideband ||
            signal == PresenceSignal.geofence,
      );
      if (!corroboratedByEnvironment) {
        return false;
      }
    }
    return true;
  }
}

enum PresenceSubmissionStatus { accepted, rejected, duplicate, expired }

final class PresenceSubmission {
  const PresenceSubmission({
    required this.eventId,
    required this.status,
    required this.recordedAt,
  });

  final String eventId;
  final PresenceSubmissionStatus status;
  final DateTime recordedAt;
}

/// Authenticated backend adapter. Presence evidence proposes an attendance
/// transition; it does not establish identity or grant physical access.
abstract interface class PresenceGateway {
  Future<PresenceChallenge> requestChallenge({
    required String doorId,
    required PresenceTransition transition,
  });

  Future<PresenceSubmission> submitEvidence({
    required PresenceChallenge challenge,
    required PresenceEvidence evidence,
    required bool automatic,
  });
}
