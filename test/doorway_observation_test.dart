import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/presence/doorway_observation.dart';

void main() {
  const codec = DoorwayObservationCodec();
  final now = DateTime.parse('2026-08-24T19:00:10Z');

  Map<String, Object?> fixtures() =>
      jsonDecode(
            File(
              'protocol/fixtures/v1/doorway-observation.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  Uint8List encode(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  test('canonical observation validates without exact location fields', () {
    final fixture = fixtures();
    final observation = codec.decodeObservation(
      encode(fixture['observation']),
      now: now,
    );
    expect(observation.challenge.houseId, 'medellin-house-1');
    expect(observation.challenge.doorId, 'front-door');
    expect(observation.signalBucket, DoorwaySignalBucket.doorway);
    expect(observation.directionRequiresConfirmation, isFalse);
    expect(observation.toString(), isNot(contains('front-door')));
    expect(observation.toString(), contains('[redacted]'));
  });

  test('only accepted backend decisions advance authoritative presence', () {
    final fixture = fixtures();
    final accepted = codec.decodeDecision(encode(fixture['decision']));
    expect(accepted.advancesAuthoritativePresence, isTrue);

    final confirmation =
        Map<String, Object?>.from(fixture['decision']! as Map<String, Object?>)
          ..['decision'] = 'confirmation_required'
          ..['reason'] = 'ambiguous_direction';
    final pending = codec.decodeDecision(encode(confirmation));
    expect(pending.advancesAuthoritativePresence, isFalse);
  });

  test('unknown precise-radio fields and duplicate keys fail closed', () {
    final fixture = fixtures();
    final observation = Map<String, Object?>.from(
      fixture['observation']! as Map<String, Object?>,
    )..['raw_rssi'] = -42;
    expect(
      () => codec.decodeObservation(encode(observation), now: now),
      throwsFormatException,
    );

    final duplicate = Uint8List.fromList(
      utf8.encode(
        '{"schema":"hhm.presence-decision.v1",'
        '"decision":"accepted","decision":"rejected",'
        '"reason":"accepted","event_id":"7a242be2-f531-4438-8a90-40e581d3800b",'
        '"observation_id":"6b8160de-67a5-42d7-9cbb-f3284f88de34",'
        '"house_id":"medellin-house-1","door_id":"front-door",'
        '"direction":"entry","presence_sequence":18,'
        '"policy_version":"presence-policy-2026-08",'
        '"recorded_at":"2026-08-24T19:00:10Z"}',
      ),
    );
    expect(() => codec.decodeDecision(duplicate), throwsFormatException);
  });

  test('same key or evidence outside the challenge window is rejected', () {
    final fixture = fixtures();
    final observation =
        jsonDecode(jsonEncode(fixture['observation'])) as Map<String, Object?>;
    final challenge = observation['challenge']! as Map<String, Object?>;
    final corroboration = observation['corroboration']! as Map<String, Object?>;
    corroboration['source_key_id'] = challenge['beacon_key_id'];
    expect(
      () => codec.decodeObservation(encode(observation), now: now),
      throwsFormatException,
    );

    corroboration['source_key_id'] = 'door-controller:front-1';
    corroboration['observed_at'] = '2026-08-24T19:00:21Z';
    expect(
      () => codec.decodeObservation(encode(observation), now: now),
      throwsFormatException,
    );
  });

  test(
    'evidence gate keeps consent, invalid, and unavailable distinct',
    () async {
      final fixture = fixtures();
      final observation = DoorwayObservation.fromJson(
        fixture['observation']! as Map<String, Object?>,
      );
      final nonce = PresenceSubmissionNonce.fromJson(
        fixture['submission_nonce']! as Map<String, Object?>,
      );
      final policy = DoorwayCollectionPolicy(
        optedIn: true,
        automaticTransitions: true,
        backgroundCollectionApproved: false,
        allowedDoorIds: const <String>{'front-door'},
      );

      final ready =
          await DoorwayEvidenceGate(
            const _Verifier(DoorwayVerification.verified),
          ).prepare(
            policy: policy,
            challenge: observation.challenge,
            corroboration: observation.corroboration,
            submissionNonce: nonce,
            now: now,
            automatic: true,
            appInForeground: true,
          );
      expect(ready.status, DoorwayPreparationStatus.ready);
      expect(ready.evidence, isNotNull);

      final unavailable =
          await DoorwayEvidenceGate(
            const _Verifier(DoorwayVerification.unavailable),
          ).prepare(
            policy: policy,
            challenge: observation.challenge,
            corroboration: observation.corroboration,
            submissionNonce: nonce,
            now: now,
            automatic: true,
            appInForeground: true,
          );
      expect(unavailable.status, DoorwayPreparationStatus.verifierUnavailable);

      final deniedPolicy = DoorwayCollectionPolicy(
        optedIn: false,
        automaticTransitions: false,
        backgroundCollectionApproved: false,
        allowedDoorIds: const <String>{'front-door'},
      );
      final denied =
          await DoorwayEvidenceGate(
            const _Verifier(DoorwayVerification.verified),
          ).prepare(
            policy: deniedPolicy,
            challenge: observation.challenge,
            corroboration: observation.corroboration,
            submissionNonce: nonce,
            now: now,
            automatic: false,
            appInForeground: true,
          );
      expect(denied.status, DoorwayPreparationStatus.consentDenied);
    },
  );
}

final class _Verifier implements DoorwayEvidenceVerifier {
  const _Verifier(this.result);

  final DoorwayVerification result;

  @override
  Future<DoorwayVerification> verify({
    required DoorwayChallenge challenge,
    required DoorwayCorroboration corroboration,
  }) async => result;
}
