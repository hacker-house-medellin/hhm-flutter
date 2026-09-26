import 'dart:convert';
import 'dart:typed_data';

import '../protocol/strict_json.dart';

const String doorwayChallengeSchema = 'hhm.doorway-challenge.v1';
const String doorwayCorroborationSchema = 'hhm.doorway-corroboration.v1';
const String doorwayObservationSchema = 'hhm.doorway-observation.v1';
const String presenceSubmissionNonceRequestSchema =
    'hhm.presence-submission-nonce-request.v1';
const String presenceSubmissionNonceSchema = 'hhm.presence-submission-nonce.v1';
const String presenceDecisionSchema = 'hhm.presence-decision.v1';
const String presenceAudience = 'hhm-presence-observation';
const int maximumDoorwayDocumentBytes = 16 * 1024;

enum DoorwayDirection { entry, exit }

enum DoorwayDirectionHint { entry, exit, ambiguous }

enum DoorwaySignalBucket { contact, doorway, near }

enum DoorwayCorroborationMethod {
  doorController,
  nfcTap,
  uwbRange,
  localNetworkChallenge,
}

final class DoorwayChallenge {
  DoorwayChallenge({
    required this.houseId,
    required this.doorId,
    required this.beaconKeyId,
    required this.keyVersion,
    required this.challengeId,
    required this.nonce,
    required this.directionHint,
    required this.issuedAt,
    required this.expiresAt,
    required this.signature,
  }) {
    _identifier('house_id', houseId);
    _identifier('door_id', doorId);
    _identifier('beacon_key_id', beaconKeyId);
    _uuid('challenge_id', challengeId);
    _base64Url('nonce', nonce, minimum: 43, maximum: 86);
    _base64Url('signature', signature, minimum: 64, maximum: 512);
    if (keyVersion < 1 || keyVersion > 2147483647) {
      throw const FormatException('Doorway beacon key version is invalid');
    }
  }

  factory DoorwayChallenge.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'schema',
      'house_id',
      'door_id',
      'beacon_key_id',
      'key_version',
      'challenge_id',
      'nonce',
      'direction_hint',
      'issued_at',
      'expires_at',
      'signature',
    });
    if (json['schema'] != doorwayChallengeSchema) {
      throw const FormatException('Unsupported doorway challenge schema');
    }
    return DoorwayChallenge(
      houseId: _string(json, 'house_id'),
      doorId: _string(json, 'door_id'),
      beaconKeyId: _string(json, 'beacon_key_id'),
      keyVersion: _integer(json, 'key_version'),
      challengeId: _string(json, 'challenge_id'),
      nonce: _string(json, 'nonce'),
      directionHint: switch (_string(json, 'direction_hint')) {
        'entry' => DoorwayDirectionHint.entry,
        'exit' => DoorwayDirectionHint.exit,
        'ambiguous' => DoorwayDirectionHint.ambiguous,
        _ => throw const FormatException('Unknown doorway direction hint'),
      },
      issuedAt: _instant(json, 'issued_at'),
      expiresAt: _instant(json, 'expires_at'),
      signature: _string(json, 'signature'),
    );
  }

  final String houseId;
  final String doorId;
  final String beaconKeyId;
  final int keyVersion;
  final String challengeId;
  final String nonce;
  final DoorwayDirectionHint directionHint;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String signature;

  void validateAt(DateTime now) {
    if (issuedAt.isAfter(now.add(const Duration(seconds: 5))) ||
        !expiresAt.isAfter(now) ||
        !expiresAt.isAfter(issuedAt) ||
        expiresAt.difference(issuedAt) > const Duration(seconds: 30)) {
      throw const FormatException(
        'Doorway challenge timestamps are expired or out of order',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': doorwayChallengeSchema,
    'house_id': houseId,
    'door_id': doorId,
    'beacon_key_id': beaconKeyId,
    'key_version': keyVersion,
    'challenge_id': challengeId,
    'nonce': nonce,
    'direction_hint': directionHint.name,
    'issued_at': _wireInstant(issuedAt),
    'expires_at': _wireInstant(expiresAt),
    'signature': signature,
  };

  @override
  String toString() =>
      'DoorwayChallenge(direction: ${directionHint.name}, proof: [redacted])';
}

final class DoorwayCorroboration {
  DoorwayCorroboration({
    required this.method,
    required this.evidenceId,
    required this.sourceKeyId,
    required this.proofDigestSha256,
    required this.distanceBucket,
    required this.observedAt,
    required this.proof,
  }) {
    _uuid('evidence_id', evidenceId);
    _identifier('source_key_id', sourceKeyId);
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(proofDigestSha256)) {
      throw const FormatException('Corroboration digest is invalid');
    }
    _base64Url('proof', proof, minimum: 64, maximum: 2048);
  }

  factory DoorwayCorroboration.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'schema',
      'method',
      'evidence_id',
      'source_key_id',
      'proof_digest_sha256',
      'distance_bucket',
      'observed_at',
      'proof',
    });
    if (json['schema'] != doorwayCorroborationSchema) {
      throw const FormatException('Unsupported doorway corroboration schema');
    }
    return DoorwayCorroboration(
      method: switch (_string(json, 'method')) {
        'door_controller' => DoorwayCorroborationMethod.doorController,
        'nfc_tap' => DoorwayCorroborationMethod.nfcTap,
        'uwb_range' => DoorwayCorroborationMethod.uwbRange,
        'local_network_challenge' =>
          DoorwayCorroborationMethod.localNetworkChallenge,
        _ => throw const FormatException('Unknown corroboration method'),
      },
      evidenceId: _string(json, 'evidence_id'),
      sourceKeyId: _string(json, 'source_key_id'),
      proofDigestSha256: _string(json, 'proof_digest_sha256'),
      distanceBucket: _signalBucket(_string(json, 'distance_bucket')),
      observedAt: _instant(json, 'observed_at'),
      proof: _string(json, 'proof'),
    );
  }

  final DoorwayCorroborationMethod method;
  final String evidenceId;
  final String sourceKeyId;
  final String proofDigestSha256;
  final DoorwaySignalBucket distanceBucket;
  final DateTime observedAt;
  final String proof;

  void validateAgainst(DoorwayChallenge challenge) {
    if (sourceKeyId == challenge.beaconKeyId ||
        observedAt.isBefore(challenge.issuedAt) ||
        observedAt.isAfter(challenge.expiresAt)) {
      throw const FormatException(
        'Corroboration is not independent and inside the challenge window',
      );
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': doorwayCorroborationSchema,
    'method': switch (method) {
      DoorwayCorroborationMethod.doorController => 'door_controller',
      DoorwayCorroborationMethod.nfcTap => 'nfc_tap',
      DoorwayCorroborationMethod.uwbRange => 'uwb_range',
      DoorwayCorroborationMethod.localNetworkChallenge =>
        'local_network_challenge',
    },
    'evidence_id': evidenceId,
    'source_key_id': sourceKeyId,
    'proof_digest_sha256': proofDigestSha256,
    'distance_bucket': distanceBucket.name,
    'observed_at': _wireInstant(observedAt),
    'proof': proof,
  };

  @override
  String toString() =>
      'DoorwayCorroboration(method: ${method.name}, proof: [redacted])';
}

final class PresenceSubmissionNonceRequest {
  PresenceSubmissionNonceRequest({required this.houseId}) {
    _identifier('house_id', houseId);
  }

  final String houseId;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': presenceSubmissionNonceRequestSchema,
    'audience': presenceAudience,
    'house_id': houseId,
  };
}

final class PresenceSubmissionNonce {
  PresenceSubmissionNonce({required this.nonce, required this.expiresAt}) {
    _base64Url('submission nonce', nonce, minimum: 43, maximum: 86);
  }

  factory PresenceSubmissionNonce.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'schema',
      'audience',
      'nonce',
      'expires_at',
    });
    if (json['schema'] != presenceSubmissionNonceSchema ||
        json['audience'] != presenceAudience) {
      throw const FormatException('Unsupported submission nonce context');
    }
    return PresenceSubmissionNonce(
      nonce: _string(json, 'nonce'),
      expiresAt: _instant(json, 'expires_at'),
    );
  }

  final String nonce;
  final DateTime expiresAt;

  void validateAt(DateTime now) {
    if (!expiresAt.isAfter(now) ||
        expiresAt.difference(now) > const Duration(minutes: 2)) {
      throw const FormatException('Submission nonce is expired or too long');
    }
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': presenceSubmissionNonceSchema,
    'audience': presenceAudience,
    'nonce': nonce,
    'expires_at': _wireInstant(expiresAt),
  };

  @override
  String toString() => 'PresenceSubmissionNonce(value: [redacted])';
}

final class DoorwayObservation {
  DoorwayObservation({
    required this.observationId,
    required this.submissionNonce,
    required this.residentDeviceKeyId,
    required this.direction,
    required this.signalBucket,
    required this.previousPresenceSequence,
    required this.policyVersion,
    required this.challenge,
    required this.corroboration,
    required this.observedAt,
    required this.deviceAttestation,
    required this.deviceSignature,
  }) {
    _uuid('observation_id', observationId);
    _base64Url('submission_nonce', submissionNonce, minimum: 43, maximum: 86);
    _identifier('resident_device_key_id', residentDeviceKeyId);
    _identifier('policy_version', policyVersion);
    _base64Url(
      'device_attestation',
      deviceAttestation,
      minimum: 64,
      maximum: 4096,
    );
    _base64Url('device_signature', deviceSignature, minimum: 64, maximum: 512);
    if (previousPresenceSequence < 0 ||
        previousPresenceSequence > 9007199254740991) {
      throw const FormatException('Previous presence sequence is invalid');
    }
  }

  factory DoorwayObservation.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'schema',
      'audience',
      'observation_id',
      'submission_nonce',
      'resident_device_key_id',
      'app_id',
      'direction',
      'signal_bucket',
      'previous_presence_sequence',
      'policy_version',
      'challenge',
      'corroboration',
      'observed_at',
      'device_attestation',
      'device_signature',
    });
    if (json['schema'] != doorwayObservationSchema ||
        json['audience'] != presenceAudience ||
        json['app_id'] != 'hhm-flutter') {
      throw const FormatException('Unsupported doorway observation context');
    }
    return DoorwayObservation(
      observationId: _string(json, 'observation_id'),
      submissionNonce: _string(json, 'submission_nonce'),
      residentDeviceKeyId: _string(json, 'resident_device_key_id'),
      direction: _direction(_string(json, 'direction')),
      signalBucket: _signalBucket(_string(json, 'signal_bucket')),
      previousPresenceSequence: _integer(json, 'previous_presence_sequence'),
      policyVersion: _string(json, 'policy_version'),
      challenge: DoorwayChallenge.fromJson(_object(json, 'challenge')),
      corroboration: DoorwayCorroboration.fromJson(
        _object(json, 'corroboration'),
      ),
      observedAt: _instant(json, 'observed_at'),
      deviceAttestation: _string(json, 'device_attestation'),
      deviceSignature: _string(json, 'device_signature'),
    );
  }

  final String observationId;
  final String submissionNonce;
  final String residentDeviceKeyId;
  final DoorwayDirection direction;
  final DoorwaySignalBucket signalBucket;
  final int previousPresenceSequence;
  final String policyVersion;
  final DoorwayChallenge challenge;
  final DoorwayCorroboration corroboration;
  final DateTime observedAt;
  final String deviceAttestation;
  final String deviceSignature;

  void validateAt(DateTime now) {
    challenge.validateAt(now);
    corroboration.validateAgainst(challenge);
    if (observedAt.isBefore(challenge.issuedAt) ||
        observedAt.isAfter(challenge.expiresAt) ||
        observedAt.isAfter(now.add(const Duration(seconds: 5)))) {
      throw const FormatException(
        'Doorway observation is outside the challenge window',
      );
    }
  }

  bool get directionRequiresConfirmation =>
      switch ((direction, challenge.directionHint)) {
        (DoorwayDirection.entry, DoorwayDirectionHint.entry) ||
        (DoorwayDirection.exit, DoorwayDirectionHint.exit) => false,
        _ => true,
      };

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': doorwayObservationSchema,
    'audience': presenceAudience,
    'observation_id': observationId,
    'submission_nonce': submissionNonce,
    'resident_device_key_id': residentDeviceKeyId,
    'app_id': 'hhm-flutter',
    'direction': direction.name,
    'signal_bucket': signalBucket.name,
    'previous_presence_sequence': previousPresenceSequence,
    'policy_version': policyVersion,
    'challenge': challenge.toJson(),
    'corroboration': corroboration.toJson(),
    'observed_at': _wireInstant(observedAt),
    'device_attestation': deviceAttestation,
    'device_signature': deviceSignature,
  };

  @override
  String toString() =>
      'DoorwayObservation(direction: ${direction.name}, evidence: [redacted])';
}

enum PresenceDecisionKind { accepted, confirmationRequired, rejected }

enum PresenceDecisionReason {
  accepted,
  ambiguousDirection,
  authenticationUnavailable,
  deviceRevoked,
  evidenceInvalid,
  expired,
  membershipDenied,
  policyConflict,
  rateLimited,
  replayed,
  unsupportedVersion,
}

final class PresenceDecision {
  PresenceDecision({
    required this.decision,
    required this.reason,
    required this.eventId,
    required this.observationId,
    required this.houseId,
    required this.doorId,
    required this.direction,
    required this.presenceSequence,
    required this.policyVersion,
    required this.recordedAt,
  }) {
    _uuid('event_id', eventId);
    _uuid('observation_id', observationId);
    _identifier('house_id', houseId);
    _identifier('door_id', doorId);
    _identifier('policy_version', policyVersion);
    if (presenceSequence < 0 || presenceSequence > 9007199254740991) {
      throw const FormatException('Presence sequence is invalid');
    }
    final consistent = switch ((decision, reason)) {
      (PresenceDecisionKind.accepted, PresenceDecisionReason.accepted) => true,
      (
        PresenceDecisionKind.confirmationRequired,
        PresenceDecisionReason.ambiguousDirection ||
            PresenceDecisionReason.policyConflict,
      ) =>
        true,
      (PresenceDecisionKind.rejected, PresenceDecisionReason.accepted) => false,
      (
        PresenceDecisionKind.rejected,
        PresenceDecisionReason.ambiguousDirection,
      ) =>
        false,
      (PresenceDecisionKind.rejected, _) => true,
      _ => false,
    };
    if (!consistent) {
      throw const FormatException('Presence decision and reason conflict');
    }
  }

  factory PresenceDecision.fromJson(Map<String, Object?> json) {
    _requireKeys(json, const <String>{
      'schema',
      'decision',
      'reason',
      'event_id',
      'observation_id',
      'house_id',
      'door_id',
      'direction',
      'presence_sequence',
      'policy_version',
      'recorded_at',
    });
    if (json['schema'] != presenceDecisionSchema) {
      throw const FormatException('Unsupported presence decision schema');
    }
    return PresenceDecision(
      decision: switch (_string(json, 'decision')) {
        'accepted' => PresenceDecisionKind.accepted,
        'confirmation_required' => PresenceDecisionKind.confirmationRequired,
        'rejected' => PresenceDecisionKind.rejected,
        _ => throw const FormatException('Unknown presence decision'),
      },
      reason: _decisionReason(_string(json, 'reason')),
      eventId: _string(json, 'event_id'),
      observationId: _string(json, 'observation_id'),
      houseId: _string(json, 'house_id'),
      doorId: _string(json, 'door_id'),
      direction: _direction(_string(json, 'direction')),
      presenceSequence: _integer(json, 'presence_sequence'),
      policyVersion: _string(json, 'policy_version'),
      recordedAt: _instant(json, 'recorded_at'),
    );
  }

  final PresenceDecisionKind decision;
  final PresenceDecisionReason reason;
  final String eventId;
  final String observationId;
  final String houseId;
  final String doorId;
  final DoorwayDirection direction;
  final int presenceSequence;
  final String policyVersion;
  final DateTime recordedAt;

  bool get advancesAuthoritativePresence =>
      decision == PresenceDecisionKind.accepted;
}

final class DoorwayObservationCodec {
  const DoorwayObservationCodec();

  DoorwayObservation decodeObservation(
    Uint8List bytes, {
    required DateTime now,
  }) {
    final value = DoorwayObservation.fromJson(
      decodeStrictJsonObject(bytes, maximumBytes: maximumDoorwayDocumentBytes),
    );
    value.validateAt(now);
    return value;
  }

  PresenceDecision decodeDecision(Uint8List bytes) => PresenceDecision.fromJson(
    decodeStrictJsonObject(bytes, maximumBytes: maximumDoorwayDocumentBytes),
  );

  Uint8List encodeObservation(
    DoorwayObservation observation, {
    required DateTime now,
  }) {
    observation.validateAt(now);
    return _boundedJson(observation.toJson());
  }

  Uint8List encodeNonceRequest(PresenceSubmissionNonceRequest request) =>
      _boundedJson(request.toJson());
}

enum DoorwayVerification { verified, invalid, unavailable }

/// Native adapters verify registered asymmetric keys and the challenge digest.
/// A verifier must never derive trust from RSSI, device name, OS pairing, or a
/// Shared Auth role. Native apps never receive protected-introspection secrets.
abstract interface class DoorwayEvidenceVerifier {
  Future<DoorwayVerification> verify({
    required DoorwayChallenge challenge,
    required DoorwayCorroboration corroboration,
  });
}

final class DoorwayCollectionPolicy {
  DoorwayCollectionPolicy({
    required this.optedIn,
    required this.automaticTransitions,
    required this.backgroundCollectionApproved,
    required Iterable<String> allowedDoorIds,
  }) : allowedDoorIds = Set.unmodifiable(allowedDoorIds);

  final bool optedIn;
  final bool automaticTransitions;
  final bool backgroundCollectionApproved;
  final Set<String> allowedDoorIds;

  bool permits({
    required DoorwayChallenge challenge,
    required bool automatic,
    required bool appInForeground,
  }) =>
      optedIn &&
      allowedDoorIds.contains(challenge.doorId) &&
      (!automatic || automaticTransitions) &&
      (appInForeground || backgroundCollectionApproved);
}

enum DoorwayPreparationStatus {
  ready,
  consentDenied,
  evidenceInvalid,
  verifierUnavailable,
}

final class DoorwayPreparation {
  const DoorwayPreparation._(this.status, this.evidence);

  final DoorwayPreparationStatus status;
  final VerifiedDoorwayEvidence? evidence;
}

final class VerifiedDoorwayEvidence {
  const VerifiedDoorwayEvidence._({
    required this.challenge,
    required this.corroboration,
    required this.submissionNonce,
  });

  final DoorwayChallenge challenge;
  final DoorwayCorroboration corroboration;
  final PresenceSubmissionNonce submissionNonce;
}

final class DoorwayEvidenceGate {
  const DoorwayEvidenceGate(this.verifier);

  final DoorwayEvidenceVerifier verifier;

  Future<DoorwayPreparation> prepare({
    required DoorwayCollectionPolicy policy,
    required DoorwayChallenge challenge,
    required DoorwayCorroboration corroboration,
    required PresenceSubmissionNonce submissionNonce,
    required DateTime now,
    required bool automatic,
    required bool appInForeground,
  }) async {
    if (!policy.permits(
      challenge: challenge,
      automatic: automatic,
      appInForeground: appInForeground,
    )) {
      return const DoorwayPreparation._(
        DoorwayPreparationStatus.consentDenied,
        null,
      );
    }
    try {
      challenge.validateAt(now);
      corroboration.validateAgainst(challenge);
      submissionNonce.validateAt(now);
    } on FormatException {
      return const DoorwayPreparation._(
        DoorwayPreparationStatus.evidenceInvalid,
        null,
      );
    }
    return switch (await verifier.verify(
      challenge: challenge,
      corroboration: corroboration,
    )) {
      DoorwayVerification.verified => DoorwayPreparation._(
        DoorwayPreparationStatus.ready,
        VerifiedDoorwayEvidence._(
          challenge: challenge,
          corroboration: corroboration,
          submissionNonce: submissionNonce,
        ),
      ),
      DoorwayVerification.invalid => const DoorwayPreparation._(
        DoorwayPreparationStatus.evidenceInvalid,
        null,
      ),
      DoorwayVerification.unavailable => const DoorwayPreparation._(
        DoorwayPreparationStatus.verifierUnavailable,
        null,
      ),
    };
  }
}

/// Hardware-backed platform adapter. It obtains an official Shared Auth-bound
/// short-lived device attestation and signs RFC 8785 canonical observation JSON
/// with domain `HHM-DOORWAY-OBSERVATION-V1\0`. It never returns a private key,
/// bearer token, or protected-introspection credential to Dart.
abstract interface class DoorwayObservationSigner {
  Future<DoorwayObservation> sign({
    required VerifiedDoorwayEvidence evidence,
    required String observationId,
    required String residentDeviceKeyId,
    required DoorwayDirection direction,
    required DoorwaySignalBucket signalBucket,
    required int previousPresenceSequence,
    required String policyVersion,
    required DateTime observedAt,
  });
}

Uint8List _boundedJson(Map<String, Object?> value) {
  final bytes = Uint8List.fromList(utf8.encode(jsonEncode(value)));
  if (bytes.isEmpty || bytes.length > maximumDoorwayDocumentBytes) {
    throw const FormatException('Doorway document size is invalid');
  }
  return bytes;
}

void _requireKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw const FormatException('Document contains unknown or missing fields');
  }
}

Map<String, Object?> _object(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! Map<String, Object?>) {
    throw FormatException('$key must be an object');
  }
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

int _integer(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! int) throw FormatException('$key must be an integer');
  return value;
}

DateTime _instant(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null || !value.isUtc) {
    throw FormatException('$key must be a UTC timestamp');
  }
  return value;
}

String _wireInstant(DateTime value) => value.toUtc().toIso8601String();

DoorwayDirection _direction(String value) => switch (value) {
  'entry' => DoorwayDirection.entry,
  'exit' => DoorwayDirection.exit,
  _ => throw const FormatException('Unknown doorway direction'),
};

DoorwaySignalBucket _signalBucket(String value) => switch (value) {
  'contact' => DoorwaySignalBucket.contact,
  'doorway' => DoorwaySignalBucket.doorway,
  'near' => DoorwaySignalBucket.near,
  _ => throw const FormatException('Unknown signal bucket'),
};

PresenceDecisionReason _decisionReason(String value) => switch (value) {
  'accepted' => PresenceDecisionReason.accepted,
  'ambiguous_direction' => PresenceDecisionReason.ambiguousDirection,
  'authentication_unavailable' =>
    PresenceDecisionReason.authenticationUnavailable,
  'device_revoked' => PresenceDecisionReason.deviceRevoked,
  'evidence_invalid' => PresenceDecisionReason.evidenceInvalid,
  'expired' => PresenceDecisionReason.expired,
  'membership_denied' => PresenceDecisionReason.membershipDenied,
  'policy_conflict' => PresenceDecisionReason.policyConflict,
  'rate_limited' => PresenceDecisionReason.rateLimited,
  'replayed' => PresenceDecisionReason.replayed,
  'unsupported_version' => PresenceDecisionReason.unsupportedVersion,
  _ => throw const FormatException('Unknown presence decision reason'),
};

void _identifier(String name, String value) {
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    throw FormatException('$name is invalid');
  }
}

void _uuid(String name, String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw FormatException('$name must be a UUID');
  }
}

void _base64Url(
  String name,
  String value, {
  required int minimum,
  required int maximum,
}) {
  if (value.length < minimum ||
      value.length > maximum ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw FormatException('$name must be bounded unpadded base64url');
  }
}
