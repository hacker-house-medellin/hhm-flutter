import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/presence/presence.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 8, 24, 12);
  final now = issuedAt.add(const Duration(seconds: 5));
  final challenge = PresenceChallenge(
    challengeId: 'challenge-1',
    nonce: '0123456789abcdef',
    doorId: 'front-door',
    transition: PresenceTransition.signIn,
    issuedAt: issuedAt,
    expiresAt: issuedAt.add(const Duration(seconds: 20)),
  );
  const policy = PresencePolicy();

  ProximityConsent consent({bool enabled = true, bool automatic = true}) =>
      ProximityConsent(
        enabled: enabled,
        automaticTransitions: automatic,
        grantedAt: issuedAt,
        allowedDoorIds: const <String>{'front-door'},
      );

  PresenceEvidence evidence(Iterable<PresenceSignal> signals) =>
      PresenceEvidence(
        challengeId: challenge.challengeId,
        challengeNonce: challenge.nonce,
        observationNonce: 'fedcba9876543210',
        observedAt: now,
        signals: signals,
      );

  test('fails closed when consent is disabled', () {
    expect(
      policy.permitsSubmission(
        consent: consent(enabled: false),
        challenge: challenge,
        evidence: evidence(const <PresenceSignal>{
          PresenceSignal.bleDoorBeacon,
          PresenceSignal.geofence,
        }),
        now: now,
        automatic: true,
      ),
      isFalse,
    );
  });

  test('requires BLE and an independent corroborating signal', () {
    expect(
      policy.permitsSubmission(
        consent: consent(),
        challenge: challenge,
        evidence: evidence(const <PresenceSignal>{
          PresenceSignal.bleDoorBeacon,
        }),
        now: now,
        automatic: true,
      ),
      isFalse,
    );
    expect(
      policy.permitsSubmission(
        consent: consent(),
        challenge: challenge,
        evidence: evidence(const <PresenceSignal>{
          PresenceSignal.bleDoorBeacon,
          PresenceSignal.geofence,
        }),
        now: now,
        automatic: true,
      ),
      isTrue,
    );
  });

  test('automatic mode requires explicit automatic consent', () {
    expect(
      policy.permitsSubmission(
        consent: consent(automatic: false),
        challenge: challenge,
        evidence: evidence(const <PresenceSignal>{
          PresenceSignal.bleDoorBeacon,
          PresenceSignal.platformNearby,
        }),
        now: now,
        automatic: true,
      ),
      isFalse,
    );
  });

  test('rejects evidence that is not bound to the challenge nonce', () {
    final mismatched = PresenceEvidence(
      challengeId: challenge.challengeId,
      challengeNonce: 'aaaaaaaaaaaaaaaa',
      observationNonce: 'bbbbbbbbbbbbbbbb',
      observedAt: now,
      signals: const <PresenceSignal>{
        PresenceSignal.bleDoorBeacon,
        PresenceSignal.geofence,
      },
    );
    expect(
      policy.permitsSubmission(
        consent: consent(),
        challenge: challenge,
        evidence: mismatched,
        now: now,
        automatic: true,
      ),
      isFalse,
    );
  });

  test('diagnostics never contain challenge material', () {
    final sample = evidence(const <PresenceSignal>{
      PresenceSignal.bleDoorBeacon,
      PresenceSignal.userConfirmation,
    });
    expect(sample.toString(), contains('identifiers: [redacted]'));
    expect(sample.toString(), isNot(contains(challenge.nonce)));
  });
}
