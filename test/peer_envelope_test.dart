import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_envelope.dart';
import 'package:hhm_flutter/src/bluetooth/peer_json_record.dart';
import 'package:hhm_flutter/src/bluetooth/peer_payload.dart';
import 'package:hhm_flutter/src/bluetooth/peer_rate_limiter.dart';
import 'package:hhm_flutter/src/bluetooth/peer_session.dart';

const sessionId = 'c15b582d-82a4-4e73-a003-5b9cf4cbcb91';
const offerId = '29145ac0-6bc9-461c-94cd-dd328b2e03aa';
const messageId = 'c9a2e32e-8a5d-4666-b0b1-aaf2adb9b00b';
const secondMessageId = '8f25ed2f-591c-4f9f-a995-b27f34d098bf';
const foregroundId = 'ForegroundLife_0123456789abcdef';

final class _Verifier implements SharedAuthPeerVerifier {
  @override
  Future<SharedAuthPeerVerification> verifyRequest(
    PeerHandshakeRequest request,
  ) async => SharedAuthPeerVerification.verified;

  @override
  Future<SharedAuthPeerVerification> verifyAcceptedTranscript({
    required PeerHandshakeRequest request,
    required PeerHandshakeResponse response,
    required Uint8List canonicalTranscript,
  }) async => SharedAuthPeerVerification.verified;
}

final class _Cipher implements PeerSessionCipher {
  _Cipher({required this.plaintext, this.reject = false});

  final Uint8List plaintext;
  final bool reject;

  @override
  Future<Uint8List> open({
    required AuthenticatedPeerSession session,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List ciphertext,
  }) async {
    if (reject) {
      throw const FormatException('AEAD tag rejected');
    }
    return Uint8List.fromList(plaintext);
  }

  @override
  Future<Uint8List> seal({
    required AuthenticatedPeerSession session,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List plaintext,
  }) async => Uint8List.fromList(plaintext);
}

final class _DeferredCipher implements PeerSessionCipher {
  _DeferredCipher(this.opened);

  final Future<Uint8List> opened;

  @override
  Future<Uint8List> open({
    required AuthenticatedPeerSession session,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List ciphertext,
  }) => opened;

  @override
  Future<Uint8List> seal({
    required AuthenticatedPeerSession session,
    required Uint8List nonce,
    required Uint8List associatedData,
    required Uint8List plaintext,
  }) async => Uint8List.fromList(plaintext);
}

final class _Context {
  const _Context(this.consent, this.session, this.replayGuard);
  final ForegroundPeerConsent consent;
  final AuthenticatedPeerSession session;
  final PeerReplayGuard replayGuard;
}

void main() {
  final now = DateTime.utc(2026, 8, 24, 18);

  Future<_Context> context({
    Set<PeerCapability> capabilities = const <PeerCapability>{
      PeerCapability.updateManifest,
    },
  }) async {
    final consent = ForegroundPeerConsent(
      selectionId: 'SelectionId_0123456789abcdef',
      selectedOfferId: offerId,
      capabilities: capabilities,
      foregroundLifecycleId: foregroundId,
      grantedAt: now.subtract(const Duration(seconds: 1)),
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final request = PeerHandshakeRequest(
      sessionId: sessionId,
      offerId: offerId,
      challengeNonce: 'BBBBBBBBBBBBBBBBBBBBBB',
      ephemeralPublicKey: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
      deviceKeyId: 'device:example-1',
      deviceAttestation:
          'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      requestedCapabilities: capabilities,
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final response = PeerHandshakeResponse(
      sessionId: sessionId,
      offerId: offerId,
      decision: PeerHandshakeDecision.accepted,
      selectedCapabilities: capabilities,
      ephemeralPublicKey: 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
      deviceKeyId: 'device:example-2',
      deviceAttestation:
          'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
      transcriptSignature:
          'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS',
      expiresAt: now.add(const Duration(minutes: 1)),
    );
    final replayGuard = PeerReplayGuard();
    final result =
        await PeerSessionAuthority(
          verifier: _Verifier(),
          replayGuard: replayGuard,
        ).establish(
          consent: consent,
          foregroundLifecycleId: foregroundId,
          request: request,
          response: response,
          now: now,
        );
    return _Context(consent, result.session!, replayGuard);
  }

  EncryptedPeerEnvelope envelope({
    String id = messageId,
    int sequence = 1,
    String nonce = 'AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcY',
    PeerPayloadType type = PeerPayloadType.updateManifest,
    String senderKeyId = 'device:example-2',
    DateTime? createdAt,
    DateTime? expiresAt,
  }) => EncryptedPeerEnvelope(
    sessionId: sessionId,
    messageId: id,
    sequence: sequence,
    payloadType: type,
    nonce: nonce,
    ciphertext: 'ZWZnaGlqa2xtbm9wcXJzdA',
    senderKeyId: senderKeyId,
    createdAt: createdAt ?? now,
    expiresAt: expiresAt ?? now.add(const Duration(seconds: 20)),
  );

  PeerEnvelopeGuard guard(
    _Context value, {
    HhmFlutterPeerPayloadPolicy payloadPolicy =
        const HhmFlutterPeerPayloadPolicy(),
  }) => PeerEnvelopeGuard(
    replayGuard: value.replayGuard,
    rateLimiter: PeerRateLimiter(),
    payloadPolicy: payloadPolicy,
  );

  SignedUpdateManifest manifest() => SignedUpdateManifest(
    appId: HhmApplicationId.flutter,
    platform: HhmReleasePlatform.android,
    channel: HhmReleaseChannel.stable,
    version: '1.2.3',
    antiRollbackCounter: 7,
    artifactSize: 1024,
    artifactSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    artifactUri: Uri.parse(
      'https://releases.example.invalid/hhm-flutter-1.2.3.apk',
    ),
    signingKeyId: 'release:example-1',
    signature:
        'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS',
    publishedAt: now,
  );

  test(
    'canonical envelope round-trips without plaintext or algorithm fields',
    () {
      final value = envelope();
      final json = value.toJson();
      expect(json['protocol_version'], 'hhm.p2p.v1');
      expect(json['payload_type'], 'hhm.update-manifest.v1');
      expect(json.containsKey('plaintext'), isFalse);
      expect(json.containsKey('algorithm'), isFalse);
      expect(EncryptedPeerEnvelope.fromJson(json).toJson(), json);
    },
  );

  test('preflight is non-mutating', () async {
    final value = await context();
    final policy = guard(value);
    final first = envelope();
    expect(
      policy
          .admit(
            consent: value.consent,
            foregroundLifecycleId: foregroundId,
            session: value.session,
            envelope: first,
            now: now,
          )
          .accepted,
      isTrue,
    );
    expect(
      policy
          .admit(
            consent: value.consent,
            foregroundLifecycleId: foregroundId,
            session: value.session,
            envelope: first,
            now: now,
          )
          .accepted,
      isTrue,
    );
  });

  test('Flutter disables canonical message/file/contact payloads', () async {
    final value = await context();
    for (final type in <PeerPayloadType>{
      PeerPayloadType.residentMessage,
      PeerPayloadType.contactCard,
      PeerPayloadType.fileManifest,
      PeerPayloadType.receipt,
    }) {
      final result = guard(value).admit(
        consent: value.consent,
        foregroundLifecycleId: foregroundId,
        session: value.session,
        envelope: envelope(type: type),
        now: now,
      );
      expect(result.rejection, PeerEnvelopeRejection.payloadDisabled);
    }
  });

  test(
    'closed JSON records require capability and explicit local consent',
    () async {
      final value = await context(
        capabilities: const <PeerCapability>{
          PeerCapability.residentMessage,
          PeerCapability.contactCard,
        },
      );
      const policy = HhmFlutterPeerPayloadPolicy(
        allowResidentMessages: true,
        allowContactCards: true,
        allowReceipts: true,
      );
      for (final type in <PeerPayloadType>{
        PeerPayloadType.residentMessage,
        PeerPayloadType.contactCard,
        PeerPayloadType.receipt,
      }) {
        final result = guard(value, payloadPolicy: policy).admit(
          consent: value.consent,
          foregroundLifecycleId: foregroundId,
          session: value.session,
          envelope: envelope(type: type),
          now: now,
        );
        expect(result.accepted, isTrue, reason: type.wireName);
      }
      expect(
        guard(value, payloadPolicy: policy)
            .admit(
              consent: value.consent,
              foregroundLifecycleId: foregroundId,
              session: value.session,
              envelope: envelope(type: PeerPayloadType.fileManifest),
              now: now,
            )
            .rejection,
        PeerEnvelopeRejection.payloadDisabled,
      );
    },
  );

  test(
    'sender key, foreground lifecycle, and 30-second lifetime are enforced',
    () async {
      final value = await context();
      expect(
        guard(value)
            .admit(
              consent: value.consent,
              foregroundLifecycleId: foregroundId,
              session: value.session,
              envelope: envelope(senderKeyId: 'device:attacker'),
              now: now,
            )
            .rejection,
        PeerEnvelopeRejection.senderKeyMismatch,
      );
      expect(
        guard(value)
            .admit(
              consent: value.consent,
              foregroundLifecycleId: 'BackgroundLife_0123456789',
              session: value.session,
              envelope: envelope(),
              now: now,
            )
            .rejection,
        PeerEnvelopeRejection.consentMissing,
      );
      expect(
        guard(value)
            .admit(
              consent: value.consent,
              foregroundLifecycleId: foregroundId,
              session: value.session,
              envelope: envelope(
                expiresAt: now.add(const Duration(seconds: 31)),
              ),
              now: now,
            )
            .rejection,
        PeerEnvelopeRejection.timingRejected,
      );
    },
  );

  test(
    'unknown fields, unknown type, and oversize ciphertext are rejected',
    () {
      final base = envelope().toJson();
      expect(
        () => EncryptedPeerEnvelope.fromJson(<String, Object?>{
          ...base,
          'bearer_token': 'forbidden',
        }),
        throwsFormatException,
      );
      expect(
        () => EncryptedPeerEnvelope.fromJson(<String, Object?>{
          ...base,
          'payload_type': 'hhm.presence-evidence.v1',
        }),
        throwsFormatException,
      );
      expect(
        () => EncryptedPeerEnvelope.fromJson(<String, Object?>{
          ...base,
          'ciphertext': List<String>.filled(12000, 'C').join(),
        }),
        throwsFormatException,
      );
    },
  );

  test('receiver decrypts only a strict signed update manifest', () async {
    final value = await context();
    const codec = PeerPayloadCodec();
    final receiver = PeerEnvelopeReceiver(
      guard: guard(value),
      cipher: _Cipher(plaintext: codec.encodeUpdateManifest(manifest())),
    );
    expect(envelope().nonceBytes, isNotEmpty);
    expect(envelope().ciphertextBytes, isNotEmpty);
    final result = await receiver.receive(
      consent: value.consent,
      foregroundLifecycleId: foregroundId,
      session: value.session,
      envelope: envelope(),
      now: now,
    );
    expect(result.accepted, isTrue, reason: result.rejection?.name);
    expect(result.manifest!.antiRollbackCounter, 7);
  });

  test(
    'receiver decrypts an explicitly consented closed JSON record',
    () async {
      final value = await context(
        capabilities: const <PeerCapability>{PeerCapability.contactCard},
      );
      const payloadPolicy = HhmFlutterPeerPayloadPolicy(
        allowContactCards: true,
      );
      final plaintext = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            'schema': 'hhm.contact-card.v1',
            'record_id': '0ad352ae-5aec-4cbd-abd5-790987f2c6b4',
            'display_alias': 'Ada',
            'fields': <Object?>[
              <String, Object?>{'kind': 'github', 'value': 'ada-resident'},
            ],
            'created_at': now
                .subtract(const Duration(seconds: 1))
                .toIso8601String(),
            'expires_at': now.add(const Duration(minutes: 1)).toIso8601String(),
          }),
        ),
      );
      final receiver = PeerEnvelopeReceiver(
        guard: guard(value, payloadPolicy: payloadPolicy),
        cipher: _Cipher(plaintext: plaintext),
      );
      final result = await receiver.receive(
        consent: value.consent,
        foregroundLifecycleId: foregroundId,
        session: value.session,
        envelope: envelope(type: PeerPayloadType.contactCard),
        now: now,
      );
      expect(result.accepted, isTrue);
      expect(result.record, isA<ContactCard>());
      expect(result.manifest, isNull);
    },
  );

  test(
    'invalid high sequence cannot poison authenticated replay state',
    () async {
      final value = await context();
      final policy = guard(value);
      final invalidReceiver = PeerEnvelopeReceiver(
        guard: policy,
        cipher: _Cipher(plaintext: Uint8List(0), reject: true),
      );
      final invalid = await invalidReceiver.receive(
        consent: value.consent,
        foregroundLifecycleId: foregroundId,
        session: value.session,
        envelope: envelope(sequence: 100),
        now: now,
      );
      expect(
        invalid.rejection,
        PeerEnvelopeRejection.decryptionOrSchemaRejected,
      );

      const codec = PeerPayloadCodec();
      final validReceiver = PeerEnvelopeReceiver(
        guard: policy,
        cipher: _Cipher(plaintext: codec.encodeUpdateManifest(manifest())),
      );
      final valid = await validReceiver.receive(
        consent: value.consent,
        foregroundLifecycleId: foregroundId,
        session: value.session,
        envelope: envelope(
          id: secondMessageId,
          sequence: 1,
          nonce: 'AgMEBQYHCAkKCwwNDg8QERITFBUWFxgZ',
        ),
        now: now,
      );
      expect(valid.accepted, isTrue, reason: valid.rejection?.name);
    },
  );

  test('concurrent authenticated commits have exactly one winner', () async {
    final value = await context();
    const codec = PeerPayloadCodec();
    final opened = Completer<Uint8List>();
    final receiver = PeerEnvelopeReceiver(
      guard: guard(value),
      cipher: _DeferredCipher(opened.future),
    );
    final sealed = envelope();
    final receives = <Future<PeerReceiveResult>>[
      receiver.receive(
        consent: value.consent,
        foregroundLifecycleId: foregroundId,
        session: value.session,
        envelope: sealed,
        now: now,
      ),
      receiver.receive(
        consent: value.consent,
        foregroundLifecycleId: foregroundId,
        session: value.session,
        envelope: sealed,
        now: now,
      ),
    ];
    opened.complete(codec.encodeUpdateManifest(manifest()));
    final results = await Future.wait(receives);

    expect(results.where((result) => result.accepted), hasLength(1));
    expect(
      results.where(
        (result) =>
            result.rejection == PeerEnvelopeRejection.replayedOrOutOfOrder,
      ),
      hasLength(1),
    );
    final repeated = await receiver.receive(
      consent: value.consent,
      foregroundLifecycleId: foregroundId,
      session: value.session,
      envelope: sealed,
      now: now,
    );
    expect(repeated.rejection, PeerEnvelopeRejection.replayedOrOutOfOrder);
  });
}
