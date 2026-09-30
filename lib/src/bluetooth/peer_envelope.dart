import 'dart:convert';
import 'dart:typed_data';

import 'peer_json_record.dart';
import 'peer_payload.dart';
import 'peer_rate_limiter.dart';
import 'peer_session.dart';

/// Exact `EncryptedEnvelope` wire object from hhm-interfaces commit ffc1df71.
/// The Flutter policy further limits decoded ciphertext to one small signed
/// update manifest or explicitly consented closed JSON record and imposes a
/// 30-second runtime lifetime in the guard.
final class EncryptedPeerEnvelope {
  EncryptedPeerEnvelope({
    required this.sessionId,
    required this.messageId,
    required this.sequence,
    required this.payloadType,
    required this.nonce,
    required this.ciphertext,
    required this.senderKeyId,
    required this.createdAt,
    required this.expiresAt,
  }) {
    _requireUuid('sessionId', sessionId);
    _requireUuid('messageId', messageId);
    _requireBase64Url('nonce', nonce, minimum: 16, maximum: 64);
    _requireBase64Url('ciphertext', ciphertext, minimum: 1, maximum: 87384);
    _requireDeviceKeyId(senderKeyId);
    final decodedCiphertext = ciphertextBytes;
    if (sequence < 0 ||
        sequence > 4294967295 ||
        decodedCiphertext.isEmpty ||
        decodedCiphertext.length >
            PeerPayloadCodec.maximumUpdateManifestBytes + 16 ||
        !expiresAt.isAfter(createdAt)) {
      throw const FormatException('Encrypted peer envelope is invalid');
    }
  }

  factory EncryptedPeerEnvelope.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'protocol_version',
      'session_id',
      'message_id',
      'sequence',
      'payload_type',
      'nonce',
      'ciphertext',
      'sender_key_id',
      'created_at',
      'expires_at',
    });
    if (json['protocol_version'] != hhmPeerProtocolVersion) {
      throw const FormatException('Unsupported encrypted envelope version');
    }
    final sequence = json['sequence'];
    if (sequence is! int) {
      throw const FormatException('sequence must be an integer');
    }
    return EncryptedPeerEnvelope(
      sessionId: _string(json, 'session_id'),
      messageId: _string(json, 'message_id'),
      sequence: sequence,
      payloadType: parsePeerPayloadType(_string(json, 'payload_type')),
      nonce: _string(json, 'nonce'),
      ciphertext: _string(json, 'ciphertext'),
      senderKeyId: _string(json, 'sender_key_id'),
      createdAt: _instant(json, 'created_at'),
      expiresAt: _instant(json, 'expires_at'),
    );
  }

  final String sessionId;
  final String messageId;
  final int sequence;
  final PeerPayloadType payloadType;
  final String nonce;
  final String ciphertext;
  final String senderKeyId;
  final DateTime createdAt;
  final DateTime expiresAt;

  Uint8List get nonceBytes => _decodeBase64Url(nonce);
  Uint8List get ciphertextBytes => _decodeBase64Url(ciphertext);

  Map<String, Object?> toJson() => <String, Object?>{
    'protocol_version': hhmPeerProtocolVersion,
    'session_id': sessionId,
    'message_id': messageId,
    'sequence': sequence,
    'payload_type': payloadType.wireName,
    'nonce': nonce,
    'ciphertext': ciphertext,
    'sender_key_id': senderKeyId,
    'created_at': createdAt.toUtc().toIso8601String(),
    'expires_at': expiresAt.toUtc().toIso8601String(),
  };

  Uint8List get associatedData => Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'protocol_version': hhmPeerProtocolVersion,
        'session_id': sessionId,
        'message_id': messageId,
        'sequence': sequence,
        'payload_type': payloadType.wireName,
        'nonce': nonce,
        'sender_key_id': senderKeyId,
        'created_at': createdAt.toUtc().toIso8601String(),
        'expires_at': expiresAt.toUtc().toIso8601String(),
      }),
    ),
  );

  Uint8List get wireBytes =>
      Uint8List.fromList(utf8.encode(jsonEncode(toJson())));

  @override
  String toString() =>
      'EncryptedPeerEnvelope(type: ${payloadType.wireName}, sequence: $sequence, '
      'session/message/ciphertext: [redacted])';
}

/// End-to-end cipher backed by the ephemeral authenticated session key. The
/// native adapter may not expose key material through this interface.
abstract interface class PeerSessionCipher {
  Future<Uint8List> seal({
    required AuthenticatedPeerSession session,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List plaintext,
  });

  Future<Uint8List> open({
    required AuthenticatedPeerSession session,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List ciphertext,
  });
}

abstract interface class ForegroundPeerTransport {
  Stream<PeerDiscoveryOffer> discover({required String foregroundLifecycleId});
  Future<void> stopDiscovery();
  Future<void> send({
    required AuthenticatedPeerSession session,
    required EncryptedPeerEnvelope envelope,
  });
  Stream<EncryptedPeerEnvelope> receive({
    required AuthenticatedPeerSession session,
  });
}

enum PeerEnvelopeRejection {
  consentMissing,
  sessionExpired,
  sessionMismatch,
  senderKeyMismatch,
  payloadDisabled,
  timingRejected,
  replayedOrOutOfOrder,
  rateLimited,
  decryptionOrSchemaRejected,
}

final class PeerEnvelopeAdmission {
  const PeerEnvelopeAdmission._({required this.accepted, this.rejection});
  const PeerEnvelopeAdmission.accepted() : this._(accepted: true);
  const PeerEnvelopeAdmission.rejected(PeerEnvelopeRejection rejection)
    : this._(accepted: false, rejection: rejection);

  final bool accepted;
  final PeerEnvelopeRejection? rejection;
}

final class PeerEnvelopeGuard {
  const PeerEnvelopeGuard({
    required this.replayGuard,
    required this.rateLimiter,
    this.payloadPolicy = const HhmFlutterPeerPayloadPolicy(),
  });

  final PeerReplayGuard replayGuard;
  final PeerRateLimiter rateLimiter;
  final HhmFlutterPeerPayloadPolicy payloadPolicy;

  PeerEnvelopeAdmission admit({
    required ForegroundPeerConsent consent,
    required String foregroundLifecycleId,
    required AuthenticatedPeerSession session,
    required EncryptedPeerEnvelope envelope,
    required DateTime now,
  }) {
    if (!consent.isActiveAt(
      now,
      foregroundLifecycleId: foregroundLifecycleId,
    )) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.consentMissing,
      );
    }
    if (!session.isActiveAt(now)) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.sessionExpired,
      );
    }
    if (consent.selectedOfferId != session.selectedOfferId ||
        envelope.sessionId != session.sessionId) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.sessionMismatch,
      );
    }
    if (envelope.senderKeyId != session.remoteDeviceKeyId) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.senderKeyMismatch,
      );
    }
    if (!payloadPolicy.allows(envelope.payloadType, session)) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.payloadDisabled,
      );
    }
    if (envelope.createdAt.isBefore(session.establishedAt) ||
        envelope.createdAt.isAfter(now) ||
        !now.isBefore(envelope.expiresAt) ||
        envelope.expiresAt.isAfter(session.expiresAt) ||
        envelope.expiresAt.difference(envelope.createdAt) >
            const Duration(seconds: 30)) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.timingRejected,
      );
    }
    if (!replayGuard.canConsumeEnvelope(
      sessionId: session.sessionId,
      messageId: envelope.messageId,
      nonce: envelope.nonce,
      sequence: envelope.sequence,
      expiresAt: envelope.expiresAt,
      now: now,
    )) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.replayedOrOutOfOrder,
      );
    }
    final rateDecision = rateLimiter.tryConsume(
      scope: session.sessionId.replaceAll('-', '_'),
      category: PeerRateCategory.encryptedEnvelope,
      byteLength: envelope.wireBytes.length,
      now: now,
    );
    if (rateDecision != PeerRateDecision.accepted) {
      return const PeerEnvelopeAdmission.rejected(
        PeerEnvelopeRejection.rateLimited,
      );
    }
    return const PeerEnvelopeAdmission.accepted();
  }

  /// Atomically records an envelope only after its AEAD tag and strict payload
  /// schema have both been authenticated. Concurrent receivers may pass
  /// [admit], but exactly one can win this synchronous commit.
  bool _commitAuthenticated({
    required AuthenticatedPeerSession session,
    required EncryptedPeerEnvelope envelope,
    required DateTime now,
  }) => replayGuard.consumeEnvelope(
    sessionId: session.sessionId,
    messageId: envelope.messageId,
    nonce: envelope.nonce,
    sequence: envelope.sequence,
    expiresAt: envelope.expiresAt,
    now: now,
  );
}

final class PeerReceiveResult {
  const PeerReceiveResult._({this.manifest, this.record, this.rejection});
  factory PeerReceiveResult.accepted(SignedUpdateManifest manifest) =>
      PeerReceiveResult._(manifest: manifest);
  factory PeerReceiveResult.acceptedRecord(PeerJsonRecord record) =>
      PeerReceiveResult._(record: record);
  const factory PeerReceiveResult.rejected(PeerEnvelopeRejection rejection) =
      _RejectedPeerReceiveResult;

  final SignedUpdateManifest? manifest;
  final PeerJsonRecord? record;
  final PeerEnvelopeRejection? rejection;
  bool get accepted =>
      (manifest != null || record != null) && rejection == null;
}

final class _RejectedPeerReceiveResult extends PeerReceiveResult {
  const _RejectedPeerReceiveResult(PeerEnvelopeRejection rejection)
    : super._(rejection: rejection);
}

final class PeerEnvelopeReceiver {
  const PeerEnvelopeReceiver({
    required this.guard,
    required this.cipher,
    this.codec = const PeerPayloadCodec(),
    this.jsonRecordCodec = const PeerJsonRecordCodec(),
  });

  final PeerEnvelopeGuard guard;
  final PeerSessionCipher cipher;
  final PeerPayloadCodec codec;
  final PeerJsonRecordCodec jsonRecordCodec;

  Future<PeerReceiveResult> receive({
    required ForegroundPeerConsent consent,
    required String foregroundLifecycleId,
    required AuthenticatedPeerSession session,
    required EncryptedPeerEnvelope envelope,
    required DateTime now,
  }) async {
    final admission = guard.admit(
      consent: consent,
      foregroundLifecycleId: foregroundLifecycleId,
      session: session,
      envelope: envelope,
      now: now,
    );
    if (!admission.accepted) {
      return PeerReceiveResult.rejected(admission.rejection!);
    }
    SignedUpdateManifest? manifest;
    PeerJsonRecord? record;
    try {
      final plaintext = await cipher.open(
        session: session,
        nonce: envelope.nonceBytes,
        associatedData: envelope.associatedData,
        ciphertext: envelope.ciphertextBytes,
      );
      switch (envelope.payloadType) {
        case PeerPayloadType.updateManifest:
          manifest = codec.decodeUpdateManifest(plaintext);
        case PeerPayloadType.residentMessage ||
            PeerPayloadType.contactCard ||
            PeerPayloadType.receipt:
          record = jsonRecordCodec.decode(
            payloadType: envelope.payloadType,
            plaintext: plaintext,
            now: now,
          );
        case PeerPayloadType.fileManifest:
          throw const FormatException('File manifests are disabled');
      }
    } on Object {
      return const PeerReceiveResult.rejected(
        PeerEnvelopeRejection.decryptionOrSchemaRejected,
      );
    }
    if (!guard._commitAuthenticated(
      session: session,
      envelope: envelope,
      now: now,
    )) {
      return const PeerReceiveResult.rejected(
        PeerEnvelopeRejection.replayedOrOutOfOrder,
      );
    }
    if (manifest case final value?) return PeerReceiveResult.accepted(value);
    return PeerReceiveResult.acceptedRecord(record!);
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

DateTime _instant(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null || !value.isUtc) {
    throw FormatException('$key must be a UTC timestamp');
  }
  return value;
}

Uint8List _decodeBase64Url(String value) {
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const FormatException('Field must be valid unpadded base64url');
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

void _requireUuid(String name, String value) {
  if (!RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value)) {
    throw FormatException('$name must be a UUID');
  }
}

void _requireDeviceKeyId(String value) {
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(value)) {
    throw const FormatException('sender key ID is invalid');
  }
}
