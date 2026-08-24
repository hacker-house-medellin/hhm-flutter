import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_session.dart';

const sessionId = 'c15b582d-82a4-4e73-a003-5b9cf4cbcb91';
const offerId = '29145ac0-6bc9-461c-94cd-dd328b2e03aa';
const otherOfferId = 'f8f44ca4-6477-49ce-a845-ae06ef514ccb';
const selectionId = 'SelectionId_0123456789abcdef';
const foregroundId = 'ForegroundLife_0123456789abcdef';

final class _Verifier implements SharedAuthPeerVerifier {
  _Verifier({this.requestAccepted = true, this.transcriptAccepted = true});

  final bool requestAccepted;
  final bool transcriptAccepted;
  int requestCalls = 0;
  int transcriptCalls = 0;

  @override
  Future<bool> verifyRequest(PeerHandshakeRequest request) async {
    requestCalls += 1;
    return requestAccepted;
  }

  @override
  Future<bool> verifyAcceptedTranscript({
    required PeerHandshakeRequest request,
    required PeerHandshakeResponse response,
    required Uint8List canonicalTranscript,
  }) async {
    transcriptCalls += 1;
    return transcriptAccepted && canonicalTranscript.isNotEmpty;
  }
}

void main() {
  final now = DateTime.utc(2026, 8, 24, 18);

  ForegroundPeerConsent consent({
    String selectedOffer = offerId,
    DateTime? expiresAt,
  }) => ForegroundPeerConsent(
    selectionId: selectionId,
    selectedOfferId: selectedOffer,
    capabilities: const <PeerCapability>{PeerCapability.updateManifest},
    foregroundLifecycleId: foregroundId,
    grantedAt: now.subtract(const Duration(seconds: 1)),
    expiresAt: expiresAt ?? now.add(const Duration(minutes: 1)),
  );

  PeerHandshakeRequest request({
    String selectedOffer = offerId,
    DateTime? expiresAt,
  }) => PeerHandshakeRequest(
    sessionId: sessionId,
    offerId: selectedOffer,
    challengeNonce: 'BBBBBBBBBBBBBBBBBBBBBB',
    ephemeralPublicKey: 'EEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEEE',
    deviceKeyId: 'device:example-1',
    deviceAttestation:
        'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
    requestedCapabilities: const <PeerCapability>{
      PeerCapability.updateManifest,
    },
    expiresAt: expiresAt ?? now.add(const Duration(minutes: 1)),
  );

  PeerHandshakeResponse response({
    String selectedOffer = offerId,
    DateTime? expiresAt,
  }) => PeerHandshakeResponse(
    sessionId: sessionId,
    offerId: selectedOffer,
    decision: PeerHandshakeDecision.accepted,
    selectedCapabilities: const <PeerCapability>{PeerCapability.updateManifest},
    ephemeralPublicKey: 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
    deviceKeyId: 'device:example-2',
    deviceAttestation:
        'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
    transcriptSignature:
        'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS',
    expiresAt: expiresAt ?? now.add(const Duration(minutes: 1)),
  );

  test('canonical request and accepted response round-trip exactly', () {
    final parsedRequest = PeerHandshakeRequest.fromJson(request().toJson());
    final parsedResponse = PeerHandshakeResponse.fromJson(response().toJson());
    expect(parsedRequest.toJson(), request().toJson());
    expect(parsedResponse.toJson(), response().toJson());
    expect(parsedRequest.toJson()['protocol_version'], 'hhm.p2p.v1');
  });

  test('accepted response must select at least one capability', () {
    expect(
      () => PeerHandshakeResponse(
        sessionId: sessionId,
        offerId: offerId,
        decision: PeerHandshakeDecision.accepted,
        selectedCapabilities: const <PeerCapability>{},
        ephemeralPublicKey: 'FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF',
        deviceKeyId: 'device:example-2',
        deviceAttestation:
            'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC',
        transcriptSignature:
            'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS',
        expiresAt: now.add(const Duration(minutes: 1)),
      ),
      throwsFormatException,
    );
  });

  test('canonical optional handshake fields reject explicit null', () {
    final wire = response().toJson()..['rejection_code'] = null;
    expect(() => PeerHandshakeResponse.fromJson(wire), throwsFormatException);
  });

  test('explicit foreground consent is lifecycle- and offer-bound', () {
    final selection = consent();
    expect(
      selection.isActiveAt(now, foregroundLifecycleId: foregroundId),
      isTrue,
    );
    expect(
      selection.isActiveAt(now, foregroundLifecycleId: 'Background_0123456789'),
      isFalse,
    );
  });

  test(
    'Shared Auth attestations establish an expiring transport session',
    () async {
      final verifier = _Verifier();
      final result =
          await PeerSessionAuthority(
            verifier: verifier,
            replayGuard: PeerReplayGuard(),
          ).establish(
            consent: consent(),
            foregroundLifecycleId: foregroundId,
            request: request(),
            response: response(),
            now: now,
          );
      expect(result.accepted, isTrue);
      expect(result.session!.capabilities, <PeerCapability>{
        PeerCapability.updateManifest,
      });
      expect(result.session!.selectedOfferId, offerId);
      expect(result.session.toString(), contains('identifiers: [redacted]'));
      expect(verifier.requestCalls, 1);
      expect(verifier.transcriptCalls, 1);
    },
  );

  test('invalid attestation and peer-selection mismatch fail closed', () async {
    final invalid =
        await PeerSessionAuthority(
          verifier: _Verifier(requestAccepted: false),
          replayGuard: PeerReplayGuard(),
        ).establish(
          consent: consent(),
          foregroundLifecycleId: foregroundId,
          request: request(),
          response: response(),
          now: now,
        );
    expect(invalid.rejection, PeerSessionRejection.attestationInvalid);

    final invalidTranscript =
        await PeerSessionAuthority(
          verifier: _Verifier(transcriptAccepted: false),
          replayGuard: PeerReplayGuard(),
        ).establish(
          consent: consent(),
          foregroundLifecycleId: foregroundId,
          request: request(),
          response: response(),
          now: now,
        );
    expect(
      invalidTranscript.rejection,
      PeerSessionRejection.attestationInvalid,
    );

    final verifier = _Verifier();
    final mismatch =
        await PeerSessionAuthority(
          verifier: verifier,
          replayGuard: PeerReplayGuard(),
        ).establish(
          consent: consent(),
          foregroundLifecycleId: foregroundId,
          request: request(selectedOffer: otherOfferId),
          response: response(selectedOffer: otherOfferId),
          now: now,
        );
    expect(mismatch.rejection, PeerSessionRejection.transcriptMismatch);
    expect(verifier.requestCalls, 0);
  });

  test('offer/challenge replay and expiry fail closed', () async {
    final authority = PeerSessionAuthority(
      verifier: _Verifier(),
      replayGuard: PeerReplayGuard(),
    );
    final first = await authority.establish(
      consent: consent(),
      foregroundLifecycleId: foregroundId,
      request: request(),
      response: response(),
      now: now,
    );
    final replay = await authority.establish(
      consent: consent(),
      foregroundLifecycleId: foregroundId,
      request: request(),
      response: response(),
      now: now,
    );
    expect(first.accepted, isTrue);
    expect(replay.rejection, PeerSessionRejection.replayed);

    final expired =
        await PeerSessionAuthority(
          verifier: _Verifier(),
          replayGuard: PeerReplayGuard(),
        ).establish(
          consent: consent(),
          foregroundLifecycleId: foregroundId,
          request: request(expiresAt: now),
          response: response(expiresAt: now),
          now: now,
        );
    expect(expired.rejection, PeerSessionRejection.expired);
  });

  test(
    'unknown fields, unsupported versions, and credentials are rejected',
    () {
      final base = request().toJson();
      for (final mutation in <Map<String, Object?>>[
        <String, Object?>{...base, 'protocol_version': 'hhm.p2p.v0'},
        <String, Object?>{...base, 'bearer_token': 'forbidden'},
        <String, Object?>{...base, 'password': 'forbidden'},
      ]) {
        expect(
          () => PeerHandshakeRequest.fromJson(mutation),
          throwsFormatException,
        );
      }
    },
  );
}
