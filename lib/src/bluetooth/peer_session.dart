import 'dart:convert';
import 'dart:typed_data';

const String hhmPeerProtocolVersion = 'hhm.p2p.v1';

enum PeerCapability {
  residentMessage('resident_message'),
  contactCard('contact_card'),
  fileManifest('file_manifest'),
  updateManifest('update_manifest');

  const PeerCapability(this.wireName);
  final String wireName;
}

PeerCapability parsePeerCapability(String value) => switch (value) {
  'resident_message' => PeerCapability.residentMessage,
  'contact_card' => PeerCapability.contactCard,
  'file_manifest' => PeerCapability.fileManifest,
  'update_manifest' => PeerCapability.updateManifest,
  _ => throw const FormatException('Unknown peer capability'),
};

/// Local rotating discovery metadata. It is deliberately not a canonical trust
/// object and contains no name, identity, role, stable device ID, or claim.
final class PeerDiscoveryOffer {
  PeerDiscoveryOffer({
    required this.offerId,
    required Iterable<PeerCapability> capabilities,
    required this.expiresAt,
  }) : capabilities = Set.unmodifiable(capabilities) {
    _requireUuid('offerId', offerId);
    if (this.capabilities.isEmpty || this.capabilities.length > 4) {
      throw const FormatException('Discovery capability set is invalid');
    }
  }

  final String offerId;
  final Set<PeerCapability> capabilities;
  final DateTime expiresAt;

  bool isDiscoverableAt(DateTime now) => now.isBefore(expiresAt);

  @override
  String toString() => 'PeerDiscoveryOffer(peer: [unverified])';
}

/// Explicit foreground selection of one rotating offer and capability set.
final class ForegroundPeerConsent {
  ForegroundPeerConsent({
    required this.selectionId,
    required this.selectedOfferId,
    required Iterable<PeerCapability> capabilities,
    required this.foregroundLifecycleId,
    required this.grantedAt,
    required this.expiresAt,
  }) : capabilities = Set.unmodifiable(capabilities) {
    _requireBase64Url('selectionId', selectionId, minimum: 22, maximum: 128);
    _requireUuid('selectedOfferId', selectedOfferId);
    _requireBase64Url(
      'foregroundLifecycleId',
      foregroundLifecycleId,
      minimum: 16,
      maximum: 128,
    );
    final lifetime = expiresAt.difference(grantedAt);
    if (this.capabilities.isEmpty ||
        this.capabilities.length > 4 ||
        lifetime <= Duration.zero ||
        lifetime > const Duration(minutes: 2)) {
      throw const FormatException('Foreground peer consent is invalid');
    }
  }

  final String selectionId;
  final String selectedOfferId;
  final Set<PeerCapability> capabilities;
  final String foregroundLifecycleId;
  final DateTime grantedAt;
  final DateTime expiresAt;

  bool isActiveAt(DateTime now, {required String foregroundLifecycleId}) =>
      this.foregroundLifecycleId == foregroundLifecycleId &&
      !now.isBefore(grantedAt) &&
      now.isBefore(expiresAt);
}

/// Exact `hhm.p2p.v1` HandshakeRequest from hhm-interfaces commit f694bc9.
final class PeerHandshakeRequest {
  PeerHandshakeRequest({
    required this.sessionId,
    required this.offerId,
    required this.challengeNonce,
    required this.ephemeralPublicKey,
    required this.deviceKeyId,
    required this.deviceAttestation,
    required Iterable<PeerCapability> requestedCapabilities,
    required this.expiresAt,
  }) : requestedCapabilities = Set.unmodifiable(requestedCapabilities) {
    _requireUuid('sessionId', sessionId);
    _requireUuid('offerId', offerId);
    _requireBase64Url(
      'challengeNonce',
      challengeNonce,
      minimum: 22,
      maximum: 86,
    );
    _requireBase64Url(
      'ephemeralPublicKey',
      ephemeralPublicKey,
      minimum: 43,
      maximum: 86,
    );
    _requireDeviceKeyId(deviceKeyId);
    _requireBase64Url(
      'deviceAttestation',
      deviceAttestation,
      minimum: 64,
      maximum: 4096,
    );
    if (this.requestedCapabilities.isEmpty ||
        this.requestedCapabilities.length > 4) {
      throw const FormatException('Requested capability set is invalid');
    }
  }

  factory PeerHandshakeRequest.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'protocol_version',
      'session_id',
      'offer_id',
      'challenge_nonce',
      'ephemeral_public_key',
      'device_key_id',
      'device_attestation',
      'requested_capabilities',
      'expires_at',
    });
    _requireProtocol(json);
    return PeerHandshakeRequest(
      sessionId: _string(json, 'session_id'),
      offerId: _string(json, 'offer_id'),
      challengeNonce: _string(json, 'challenge_nonce'),
      ephemeralPublicKey: _string(json, 'ephemeral_public_key'),
      deviceKeyId: _string(json, 'device_key_id'),
      deviceAttestation: _string(json, 'device_attestation'),
      requestedCapabilities: _stringList(
        json['requested_capabilities'],
      ).map(parsePeerCapability),
      expiresAt: _instant(json, 'expires_at'),
    );
  }

  final String sessionId;
  final String offerId;
  final String challengeNonce;
  final String ephemeralPublicKey;
  final String deviceKeyId;
  final String deviceAttestation;
  final Set<PeerCapability> requestedCapabilities;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': hhmPeerProtocolVersion,
    'session_id': sessionId,
    'offer_id': offerId,
    'challenge_nonce': challengeNonce,
    'ephemeral_public_key': ephemeralPublicKey,
    'device_key_id': deviceKeyId,
    'device_attestation': deviceAttestation,
    'requested_capabilities':
        requestedCapabilities.map((value) => value.wireName).toList()..sort(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  @override
  String toString() => 'PeerHandshakeRequest(material: [redacted])';
}

enum PeerHandshakeDecision { accepted, rejected }

enum PeerHandshakeRejectionCode {
  consentDeclined('consent_declined'),
  expired('expired'),
  replayed('replayed'),
  attestationInvalid('attestation_invalid'),
  capabilityDenied('capability_denied'),
  rateLimited('rate_limited'),
  unsupportedVersion('unsupported_version');

  const PeerHandshakeRejectionCode(this.wireName);
  final String wireName;
}

/// Exact `hhm.p2p.v1` HandshakeResponse from hhm-interfaces commit f694bc9.
final class PeerHandshakeResponse {
  PeerHandshakeResponse({
    required this.sessionId,
    required this.offerId,
    required this.decision,
    required Iterable<PeerCapability> selectedCapabilities,
    required this.expiresAt,
    this.ephemeralPublicKey,
    this.deviceKeyId,
    this.deviceAttestation,
    this.transcriptSignature,
    this.rejectionCode,
  }) : selectedCapabilities = Set.unmodifiable(selectedCapabilities) {
    _requireUuid('sessionId', sessionId);
    _requireUuid('offerId', offerId);
    if (this.selectedCapabilities.length > 4) {
      throw const FormatException('Selected capability set is invalid');
    }
    if (decision == PeerHandshakeDecision.accepted) {
      if (this.selectedCapabilities.isEmpty ||
          ephemeralPublicKey == null ||
          deviceKeyId == null ||
          deviceAttestation == null ||
          transcriptSignature == null ||
          rejectionCode != null) {
        throw const FormatException('Accepted handshake fields are incomplete');
      }
      _requireBase64Url(
        'ephemeralPublicKey',
        ephemeralPublicKey!,
        minimum: 43,
        maximum: 86,
      );
      _requireDeviceKeyId(deviceKeyId!);
      _requireBase64Url(
        'deviceAttestation',
        deviceAttestation!,
        minimum: 64,
        maximum: 4096,
      );
      _requireBase64Url(
        'transcriptSignature',
        transcriptSignature!,
        minimum: 64,
        maximum: 512,
      );
    } else if (this.selectedCapabilities.isNotEmpty ||
        rejectionCode == null ||
        ephemeralPublicKey != null ||
        deviceKeyId != null ||
        deviceAttestation != null ||
        transcriptSignature != null) {
      throw const FormatException('Rejected handshake fields are invalid');
    }
  }

  factory PeerHandshakeResponse.fromJson(Map<String, Object?> json) {
    const allowed = <String>{
      'protocol_version',
      'session_id',
      'offer_id',
      'decision',
      'selected_capabilities',
      'ephemeral_public_key',
      'device_key_id',
      'device_attestation',
      'transcript_signature',
      'rejection_code',
      'expires_at',
    };
    const required = <String>{
      'protocol_version',
      'session_id',
      'offer_id',
      'decision',
      'selected_capabilities',
      'expires_at',
    };
    if (json.keys.toSet().difference(allowed).isNotEmpty ||
        required.difference(json.keys.toSet()).isNotEmpty) {
      throw const FormatException('Handshake response fields are invalid');
    }
    _requireProtocol(json);
    final decision = switch (_string(json, 'decision')) {
      'accepted' => PeerHandshakeDecision.accepted,
      'rejected' => PeerHandshakeDecision.rejected,
      _ => throw const FormatException('Unknown handshake decision'),
    };
    return PeerHandshakeResponse(
      sessionId: _string(json, 'session_id'),
      offerId: _string(json, 'offer_id'),
      decision: decision,
      selectedCapabilities: _stringList(
        json['selected_capabilities'],
      ).map(parsePeerCapability),
      ephemeralPublicKey: _optionalString(json, 'ephemeral_public_key'),
      deviceKeyId: _optionalString(json, 'device_key_id'),
      deviceAttestation: _optionalString(json, 'device_attestation'),
      transcriptSignature: _optionalString(json, 'transcript_signature'),
      rejectionCode: _optionalRejection(json, 'rejection_code'),
      expiresAt: _instant(json, 'expires_at'),
    );
  }

  final String sessionId;
  final String offerId;
  final PeerHandshakeDecision decision;
  final Set<PeerCapability> selectedCapabilities;
  final String? ephemeralPublicKey;
  final String? deviceKeyId;
  final String? deviceAttestation;
  final String? transcriptSignature;
  final PeerHandshakeRejectionCode? rejectionCode;
  final DateTime expiresAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': hhmPeerProtocolVersion,
    'session_id': sessionId,
    'offer_id': offerId,
    'decision': decision.name,
    'selected_capabilities':
        selectedCapabilities.map((value) => value.wireName).toList()..sort(),
    if (ephemeralPublicKey != null) 'ephemeral_public_key': ephemeralPublicKey,
    if (deviceKeyId != null) 'device_key_id': deviceKeyId,
    if (deviceAttestation != null) 'device_attestation': deviceAttestation,
    if (transcriptSignature != null)
      'transcript_signature': transcriptSignature,
    if (rejectionCode != null) 'rejection_code': rejectionCode!.wireName,
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };
}

/// Verifies official Shared Auth audience/client/session/device binding and both
/// device-bound signatures. Attestations are proofs, not transferable tokens.
enum SharedAuthPeerVerification { verified, invalid, unavailable }

abstract interface class SharedAuthPeerVerifier {
  Future<SharedAuthPeerVerification> verifyRequest(
    PeerHandshakeRequest request,
  );

  Future<SharedAuthPeerVerification> verifyAcceptedTranscript({
    required PeerHandshakeRequest request,
    required PeerHandshakeResponse response,
    required Uint8List canonicalTranscript,
  });
}

final class AuthenticatedPeerSession {
  AuthenticatedPeerSession._({
    required this.sessionId,
    required this.selectedOfferId,
    required this.remoteDeviceKeyId,
    required Iterable<PeerCapability> capabilities,
    required this.establishedAt,
    required this.expiresAt,
  }) : capabilities = Set.unmodifiable(capabilities);

  final String sessionId;
  final String selectedOfferId;
  final String remoteDeviceKeyId;
  final Set<PeerCapability> capabilities;
  final DateTime establishedAt;
  final DateTime expiresAt;

  bool isActiveAt(DateTime now) =>
      !now.isBefore(establishedAt) && now.isBefore(expiresAt);

  @override
  String toString() =>
      'AuthenticatedPeerSession(capabilities: ${capabilities.length}, '
      'identifiers: [redacted])';
}

enum PeerSessionRejection {
  consentMissing,
  expired,
  peerRejected,
  transcriptMismatch,
  capabilityDenied,
  attestationInvalid,
  authenticationUnavailable,
  replayed,
  capacityExceeded,
}

final class PeerSessionResult {
  const PeerSessionResult._({this.session, this.rejection});

  factory PeerSessionResult.accepted(AuthenticatedPeerSession session) =>
      PeerSessionResult._(session: session);

  const factory PeerSessionResult.rejected(PeerSessionRejection rejection) =
      _RejectedPeerSessionResult;

  final AuthenticatedPeerSession? session;
  final PeerSessionRejection? rejection;
  bool get accepted => session != null && rejection == null;
}

final class _RejectedPeerSessionResult extends PeerSessionResult {
  const _RejectedPeerSessionResult(PeerSessionRejection rejection)
    : super._(rejection: rejection);
}

final class PeerReplayGuard {
  PeerReplayGuard({this.maximumTrackedValues = 4096});

  final int maximumTrackedValues;
  final Map<String, DateTime> _offers = <String, DateTime>{};
  final Map<String, DateTime> _sessions = <String, DateTime>{};
  final Map<String, DateTime> _messages = <String, DateTime>{};
  final Map<String, int> _lastSequences = <String, int>{};

  bool consumeHandshake(PeerHandshakeRequest request, DateTime now) {
    _purge(now);
    final key = '${request.offerId}:${request.challengeNonce}';
    if (!now.isBefore(request.expiresAt) ||
        _offers.containsKey(key) ||
        _trackedCount >= maximumTrackedValues) {
      return false;
    }
    _offers[key] = request.expiresAt;
    return true;
  }

  bool registerSession(String sessionId, DateTime expiresAt, DateTime now) {
    _purge(now);
    if (!now.isBefore(expiresAt) ||
        _sessions.containsKey(sessionId) ||
        _trackedCount >= maximumTrackedValues) {
      return false;
    }
    _sessions[sessionId] = expiresAt;
    return true;
  }

  bool canConsumeEnvelope({
    required String sessionId,
    required String messageId,
    required String nonce,
    required int sequence,
    required DateTime expiresAt,
    required DateTime now,
  }) {
    _purge(now);
    final messageKey = '$sessionId:$messageId:$nonce';
    final lastSequence = _lastSequences[sessionId];
    return now.isBefore(expiresAt) &&
        _sessions.containsKey(sessionId) &&
        !_messages.containsKey(messageKey) &&
        (lastSequence == null || sequence > lastSequence) &&
        _trackedCount < maximumTrackedValues;
  }

  bool consumeEnvelope({
    required String sessionId,
    required String messageId,
    required String nonce,
    required int sequence,
    required DateTime expiresAt,
    required DateTime now,
  }) {
    if (!canConsumeEnvelope(
      sessionId: sessionId,
      messageId: messageId,
      nonce: nonce,
      sequence: sequence,
      expiresAt: expiresAt,
      now: now,
    )) {
      return false;
    }
    _messages['$sessionId:$messageId:$nonce'] = expiresAt;
    _lastSequences[sessionId] = sequence;
    return true;
  }

  int get _trackedCount => _offers.length + _sessions.length + _messages.length;

  void _purge(DateTime now) {
    _offers.removeWhere((_, expiry) => !now.isBefore(expiry));
    _sessions.removeWhere((sessionId, expiry) {
      final expired = !now.isBefore(expiry);
      if (expired) {
        _lastSequences.remove(sessionId);
      }
      return expired;
    });
    _messages.removeWhere((_, expiry) => !now.isBefore(expiry));
  }
}

final class PeerSessionAuthority {
  const PeerSessionAuthority({
    required this.verifier,
    required this.replayGuard,
  });

  final SharedAuthPeerVerifier verifier;
  final PeerReplayGuard replayGuard;

  Future<PeerSessionResult> establish({
    required ForegroundPeerConsent consent,
    required String foregroundLifecycleId,
    required PeerHandshakeRequest request,
    required PeerHandshakeResponse response,
    required DateTime now,
  }) async {
    if (!consent.isActiveAt(
      now,
      foregroundLifecycleId: foregroundLifecycleId,
    )) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.consentMissing,
      );
    }
    if (!now.isBefore(request.expiresAt) ||
        !now.isBefore(response.expiresAt) ||
        request.expiresAt.isAfter(now.add(const Duration(minutes: 2))) ||
        response.expiresAt.isAfter(now.add(const Duration(minutes: 2)))) {
      return const PeerSessionResult.rejected(PeerSessionRejection.expired);
    }
    if (response.decision != PeerHandshakeDecision.accepted) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.peerRejected,
      );
    }
    if (consent.selectedOfferId != request.offerId ||
        request.offerId != response.offerId ||
        request.sessionId != response.sessionId) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.transcriptMismatch,
      );
    }
    if (!consent.capabilities.containsAll(request.requestedCapabilities) ||
        !request.requestedCapabilities.containsAll(
          response.selectedCapabilities,
        ) ||
        response.selectedCapabilities.isEmpty) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.capabilityDenied,
      );
    }

    SharedAuthPeerVerification requestVerification;
    try {
      requestVerification = await verifier.verifyRequest(request);
    } on Object {
      requestVerification = SharedAuthPeerVerification.unavailable;
    }
    if (requestVerification == SharedAuthPeerVerification.unavailable) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.authenticationUnavailable,
      );
    }
    if (requestVerification == SharedAuthPeerVerification.invalid) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.attestationInvalid,
      );
    }

    SharedAuthPeerVerification transcriptVerification;
    try {
      transcriptVerification = await verifier.verifyAcceptedTranscript(
        request: request,
        response: response,
        canonicalTranscript: _canonicalTranscript(request, response),
      );
    } on Object {
      transcriptVerification = SharedAuthPeerVerification.unavailable;
    }
    if (transcriptVerification == SharedAuthPeerVerification.unavailable) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.authenticationUnavailable,
      );
    }
    if (transcriptVerification == SharedAuthPeerVerification.invalid) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.attestationInvalid,
      );
    }
    if (!replayGuard.consumeHandshake(request, now)) {
      return const PeerSessionResult.rejected(PeerSessionRejection.replayed);
    }

    var expiresAt = consent.expiresAt;
    for (final candidate in <DateTime>[
      request.expiresAt,
      response.expiresAt,
      now.add(const Duration(minutes: 30)),
    ]) {
      if (candidate.isBefore(expiresAt)) {
        expiresAt = candidate;
      }
    }
    if (!replayGuard.registerSession(request.sessionId, expiresAt, now)) {
      return const PeerSessionResult.rejected(
        PeerSessionRejection.capacityExceeded,
      );
    }
    return PeerSessionResult.accepted(
      AuthenticatedPeerSession._(
        sessionId: request.sessionId,
        selectedOfferId: request.offerId,
        remoteDeviceKeyId: response.deviceKeyId!,
        capabilities: response.selectedCapabilities,
        establishedAt: now,
        expiresAt: expiresAt,
      ),
    );
  }
}

Uint8List _canonicalTranscript(
  PeerHandshakeRequest request,
  PeerHandshakeResponse response,
) => Uint8List.fromList(
  utf8.encode(
    jsonEncode(<String, Object?>{
      'protocol_version': hhmPeerProtocolVersion,
      'request': request.toJson(),
      'response': response.toJson(),
    }),
  ),
);

void _requireProtocol(Map<String, Object?> json) {
  if (json['protocol_version'] != hhmPeerProtocolVersion) {
    throw const FormatException('Unsupported peer protocol version');
  }
}

void _requireExactKeys(Map<String, Object?> value, Set<String> expected) {
  if (value.keys.toSet().difference(expected).isNotEmpty ||
      expected.difference(value.keys.toSet()).isNotEmpty) {
    throw const FormatException('Document contains unknown or missing fields');
  }
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string');
  }
  return value;
}

String? _optionalString(Map<String, Object?> json, String key) {
  if (!json.containsKey(key)) {
    return null;
  }
  final value = json[key];
  if (value is! String) {
    throw FormatException('$key must be a string');
  }
  return value;
}

DateTime _instant(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null || !value.isUtc) {
    throw FormatException('$key must be a UTC timestamp');
  }
  return value;
}

List<String> _stringList(Object? value) {
  if (value is! List<Object?> || value.any((entry) => entry is! String)) {
    throw const FormatException('Expected a string list');
  }
  final strings = value.cast<String>();
  if (strings.toSet().length != strings.length) {
    throw const FormatException('List items must be unique');
  }
  return strings;
}

PeerHandshakeRejectionCode? _optionalRejection(
  Map<String, Object?> json,
  String key,
) {
  if (!json.containsKey(key)) {
    return null;
  }
  final value = json[key];
  if (value is! String) {
    throw const FormatException('rejection_code must be a string');
  }
  return switch (value) {
    'consent_declined' => PeerHandshakeRejectionCode.consentDeclined,
    'expired' => PeerHandshakeRejectionCode.expired,
    'replayed' => PeerHandshakeRejectionCode.replayed,
    'attestation_invalid' => PeerHandshakeRejectionCode.attestationInvalid,
    'capability_denied' => PeerHandshakeRejectionCode.capabilityDenied,
    'rate_limited' => PeerHandshakeRejectionCode.rateLimited,
    'unsupported_version' => PeerHandshakeRejectionCode.unsupportedVersion,
    _ => throw const FormatException('Unknown handshake rejection code'),
  };
}

void _requireUuid(String name, String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw FormatException('$name must be a UUID');
  }
}

void _requireDeviceKeyId(String value) {
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    throw const FormatException('device key ID is invalid');
  }
}

void _requireBase64Url(
  String name,
  String value, {
  required int minimum,
  required int maximum,
}) {
  if (value.length < minimum ||
      value.length > maximum ||
      !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(value)) {
    throw FormatException('$name must be an unpadded base64url value');
  }
}
