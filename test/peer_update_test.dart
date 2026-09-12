import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_payload.dart';
import 'package:hhm_flutter/src/bluetooth/peer_update.dart';

const releaseKeyId = 'release:example-1';

final class _Verifier implements ReleaseSignatureVerifier {
  _Verifier(this.accept, {this.throwError = false});
  final bool accept;
  final bool throwError;
  int calls = 0;
  Uint8List? canonicalManifest;

  @override
  Future<bool> verifyEd25519({
    required Uint8List publicKey,
    required Uint8List canonicalManifest,
    required Uint8List signature,
  }) async {
    calls += 1;
    this.canonicalManifest = Uint8List.fromList(canonicalManifest);
    if (throwError) {
      throw const FormatException('crypto adapter rejected');
    }
    return accept;
  }
}

final class _Installer implements OfficialPlatformReleaseInstaller {
  int calls = 0;
  VerifiedOfficialRelease? installed;

  @override
  Future<void> install(VerifiedOfficialRelease release) async {
    calls += 1;
    installed = release;
  }
}

void main() {
  final now = DateTime.utc(2026, 8, 24, 18);

  SignedUpdateManifest manifest({
    HhmApplicationId appId = HhmApplicationId.flutter,
    HhmReleasePlatform platform = HhmReleasePlatform.android,
    HhmReleaseChannel channel = HhmReleaseChannel.stable,
    int counter = 7,
    int artifactSize = 1024,
    Uri? artifactUri,
    String keyId = releaseKeyId,
    DateTime? publishedAt,
  }) => SignedUpdateManifest(
    appId: appId,
    platform: platform,
    channel: channel,
    version: '1.2.3',
    antiRollbackCounter: counter,
    artifactSize: artifactSize,
    artifactSha256:
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    artifactUri:
        artifactUri ??
        Uri.parse('https://releases.example.invalid/hhm-flutter-1.2.3.apk'),
    signingKeyId: keyId,
    signature:
        'SSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSSS',
    publishedAt: publishedAt ?? now.subtract(const Duration(minutes: 1)),
  );

  PeerUpdateCoordinator coordinator({
    HhmReleasePlatform platform = HhmReleasePlatform.android,
    HhmReleaseChannel channel = HhmReleaseChannel.stable,
    int installedCounter = 6,
    _Verifier? verifier,
    _Installer? installer,
    int maximumArtifactBytes = 500 * 1024 * 1024,
  }) => PeerUpdateCoordinator(
    installed: InstalledApplication(
      appId: HhmApplicationId.flutter,
      platform: platform,
      channel: channel,
      version: '1.2.2',
      antiRollbackCounter: installedCounter,
    ),
    releaseKey: PinnedReleaseSigningKey(
      keyId: releaseKeyId,
      publicKey: Uint8List.fromList(List<int>.filled(32, 9)),
    ),
    originPolicy: OfficialReleaseOriginPolicy(<Uri>[
      Uri.parse('https://releases.example.invalid'),
    ]),
    signatureVerifier: verifier ?? _Verifier(true),
    installer: installer ?? _Installer(),
    maximumArtifactBytes: maximumArtifactBytes,
  );

  test('pinned signature yields an official-install-only release', () async {
    final verifier = _Verifier(true);
    final installer = _Installer();
    final updates = coordinator(verifier: verifier, installer: installer);
    final result = await updates.verifyManifest(manifest(), now: now);

    expect(result.accepted, isTrue);
    expect(verifier.calls, 1);
    expect(verifier.canonicalManifest, manifest().canonicalUnsignedBytes);
    expect(
      result.release.toString(),
      contains('artifact: [official/redacted]'),
    );

    await updates.install(result.release!);
    expect(installer.calls, 1);
    expect(installer.installed, same(result.release));
  });

  test('anti-rollback counter rejects downgrade and same release', () async {
    final verifier = _Verifier(true);
    for (final counter in <int>[5, 6]) {
      final result = await coordinator(
        installedCounter: 6,
        verifier: verifier,
      ).verifyManifest(manifest(counter: counter), now: now);
      expect(result.rejection, PeerUpdateRejection.rollbackOrSameCounter);
    }
    expect(verifier.calls, 0);
  });

  test(
    'application, platform, and channel must match the current binary',
    () async {
      expect(
        (await coordinator().verifyManifest(
          manifest(appId: HhmApplicationId.desktopRust),
          now: now,
        )).rejection,
        PeerUpdateRejection.wrongApplication,
      );
      expect(
        (await coordinator().verifyManifest(
          manifest(platform: HhmReleasePlatform.ios),
          now: now,
        )).rejection,
        PeerUpdateRejection.wrongPlatform,
      );
      expect(
        (await coordinator().verifyManifest(
          manifest(channel: HhmReleaseChannel.beta),
          now: now,
        )).rejection,
        PeerUpdateRejection.channelMismatch,
      );
    },
  );

  test('artifact URL must be official HTTPS with no bearer query', () async {
    for (final uri in <Uri>[
      Uri.parse('https://peer.example/hhm.apk'),
      Uri.parse('https://releases.example.invalid/hhm.apk?token=bearer'),
    ]) {
      final result = await coordinator().verifyManifest(
        manifest(artifactUri: uri),
        now: now,
      );
      expect(
        result.rejection,
        PeerUpdateRejection.unofficialArtifactOrigin,
        reason: uri.toString(),
      );
    }
  });

  test('unknown key and invalid signature fail closed', () async {
    expect(
      (await coordinator().verifyManifest(
        manifest(keyId: 'release:attacker'),
        now: now,
      )).rejection,
      PeerUpdateRejection.releaseKeyMismatch,
    );
    expect(
      (await coordinator(
        verifier: _Verifier(false),
      ).verifyManifest(manifest(), now: now)).rejection,
      PeerUpdateRejection.signatureRejected,
    );
    expect(
      (await coordinator(
        verifier: _Verifier(true, throwError: true),
      ).verifyManifest(manifest(), now: now)).rejection,
      PeerUpdateRejection.signatureRejected,
    );
  });

  test('artifact size and publication time are bounded', () async {
    expect(
      (await coordinator(
        maximumArtifactBytes: 1024,
      ).verifyManifest(manifest(artifactSize: 1025), now: now)).rejection,
      PeerUpdateRejection.artifactSizeRejected,
    );
    expect(
      (await coordinator().verifyManifest(
        manifest(publishedAt: now.add(const Duration(seconds: 1))),
        now: now,
      )).rejection,
      PeerUpdateRejection.futureManifest,
    );
  });
}
