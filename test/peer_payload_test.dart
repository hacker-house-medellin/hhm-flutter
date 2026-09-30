import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_payload.dart';

void main() {
  const codec = PeerPayloadCodec();
  final now = DateTime.utc(2026, 8, 24, 18);

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

  test('canonical signed update manifest round-trips exactly', () {
    final value = manifest();
    final decoded = codec.decodeUpdateManifest(
      codec.encodeUpdateManifest(value),
    );
    expect(decoded.toJson(), value.toJson());
    expect(decoded.toJson()['schema'], 'hhm.update-manifest.v1');
    expect(decoded.toJson()['app_id'], 'hhm-flutter');
  });

  test('canonical unsigned bytes exclude only the signature', () {
    final value = manifest();
    final canonical = utf8.decode(value.canonicalUnsignedBytes);
    expect(canonical, contains('"anti_rollback_counter":7'));
    expect(canonical, contains('"artifact_sha256"'));
    expect(canonical, isNot(contains('"signature"')));
  });

  test('strict schema rejects peer content, credentials, and executables', () {
    final base = manifest().toJson();
    for (final forbidden in <String, Object?>{
      'conversation': 'raw transcript',
      'camera_frame': 'raw image',
      'latitude': 6.2442,
      'bearer_token': 'secret',
      'private_key': 'secret',
      'executable_bytes': 'peer code',
      'wasm_module': 'peer code',
    }.entries) {
      final bytes = Uint8List.fromList(
        utf8.encode(
          jsonEncode(<String, Object?>{
            ...base,
            forbidden.key: forbidden.value,
          }),
        ),
      );
      expect(
        () => codec.decodeUpdateManifest(bytes),
        throwsFormatException,
        reason: forbidden.key,
      );
    }
  });

  test('canonical type parser has no presence or door-unlock type', () {
    expect(
      parsePeerPayloadType('hhm.update-manifest.v1'),
      PeerPayloadType.updateManifest,
    );
    expect(
      () => parsePeerPayloadType('hhm.presence-evidence.v1'),
      throwsFormatException,
    );
    expect(
      () => parsePeerPayloadType('hhm.door-unlock.v1'),
      throwsFormatException,
    );
  });

  test('malformed, unknown, and oversized manifests fail closed', () {
    expect(
      () => SignedUpdateManifest.fromJson(<String, Object?>{
        ...manifest().toJson(),
        'app_id': 'unknown-app',
      }),
      throwsFormatException,
    );
    expect(
      () => codec.decodeUpdateManifest(
        Uint8List(PeerPayloadCodec.maximumUpdateManifestBytes + 1),
      ),
      throwsFormatException,
    );
  });
}
