import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_envelope.dart';
import 'package:hhm_flutter/src/bluetooth/peer_payload.dart';
import 'package:hhm_flutter/src/bluetooth/peer_session.dart';

const _canonicalCommit = 'f694bc9b58907db918f0449b5d04a5763f8fa745';
const _canonicalFixtureDigest =
    'cc8c94f006db484196645056878342eccb6ad39c6ec42a77928ff35c6bdc92d8';
const _timeKeys = <String>{'created_at', 'expires_at', 'published_at'};

void main() {
  test('vendored fixture is the exact f694bc9 canonical fixture', () async {
    final dependency = _jsonObject(
      jsonDecode(
        await File('protocol/CANONICAL_INTERFACE.json').readAsString(),
      ),
    );
    final fixtureBytes = await File(
      'protocol/fixtures/v1/peer-session.json',
    ).readAsBytes();

    expect(dependency['commit'], _canonicalCommit);
    expect(dependency['protocol_version'], hhmPeerProtocolVersion);
    expect(dependency['fixture_sha256'], _canonicalFixtureDigest);
    expect(sha256.convert(fixtureBytes).toString(), _canonicalFixtureDigest);
  });

  test('all canonical wire objects parse and round trip', () async {
    final fixture = _jsonObject(
      jsonDecode(
        await File('protocol/fixtures/v1/peer-session.json').readAsString(),
      ),
    );

    final requestJson = _jsonObject(fixture['handshake_request']);
    final responseJson = _jsonObject(fixture['handshake_response']);
    final envelopeJson = _jsonObject(fixture['encrypted_envelope']);
    final manifestJson = _jsonObject(fixture['signed_update_manifest']);

    final request = PeerHandshakeRequest.fromJson(requestJson);
    final response = PeerHandshakeResponse.fromJson(responseJson);
    final envelope = EncryptedPeerEnvelope.fromJson(envelopeJson);
    final manifest = SignedUpdateManifest.fromJson(manifestJson);

    expect(
      _normalizeWireTimes(request.toJson()),
      _normalizeWireTimes(requestJson),
    );
    expect(
      _normalizeWireTimes(response.toJson()),
      _normalizeWireTimes(responseJson),
    );
    expect(
      _normalizeWireTimes(envelope.toJson()),
      _normalizeWireTimes(envelopeJson),
    );
    expect(
      _normalizeWireTimes(manifest.toJson()),
      _normalizeWireTimes(manifestJson),
    );
    expect(response.selectedCapabilities, isNotEmpty);
    expect(envelope.payloadType, PeerPayloadType.updateManifest);
  });
}

Map<String, Object?> _jsonObject(Object? value) {
  if (value is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object');
  }
  return value;
}

Map<String, Object?> _normalizeWireTimes(Map<String, Object?> value) =>
    value.map((key, item) {
      if (_timeKeys.contains(key) && item is String) {
        return MapEntry(key, DateTime.parse(item).toUtc().toIso8601String());
      }
      return MapEntry(key, item);
    });
