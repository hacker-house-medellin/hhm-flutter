import 'dart:convert';
import 'dart:typed_data';

import 'peer_payload.dart';

final class PinnedReleaseSigningKey {
  PinnedReleaseSigningKey({required this.keyId, required Uint8List publicKey})
    : publicKey = Uint8List.fromList(publicKey) {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(keyId) ||
        this.publicKey.length != 32 ||
        this.publicKey.every((byte) => byte == 0)) {
      throw const FormatException('Pinned Ed25519 release key is invalid');
    }
  }

  final String keyId;
  final Uint8List publicKey;

  @override
  String toString() =>
      'PinnedReleaseSigningKey(keyId: $keyId, key: [redacted])';
}

final class InstalledApplication {
  const InstalledApplication({
    required this.appId,
    required this.platform,
    required this.channel,
    required this.version,
    required this.antiRollbackCounter,
  });

  final HhmApplicationId appId;
  final HhmReleasePlatform platform;
  final HhmReleaseChannel channel;
  final String version;
  final int antiRollbackCounter;
}

final class OfficialReleaseOriginPolicy {
  OfficialReleaseOriginPolicy(Iterable<Uri> origins)
    : origins = Set.unmodifiable(origins) {
    if (this.origins.isEmpty ||
        this.origins.any(
          (origin) =>
              origin.scheme != 'https' ||
              !origin.hasAuthority ||
              origin.userInfo.isNotEmpty ||
              origin.path.isNotEmpty ||
              origin.query.isNotEmpty ||
              origin.fragment.isNotEmpty,
        )) {
      throw const FormatException(
        'Official release origins must be HTTPS origins',
      );
    }
  }

  final Set<Uri> origins;

  bool allows(Uri uri) =>
      uri.scheme == 'https' &&
      uri.hasAuthority &&
      uri.userInfo.isEmpty &&
      uri.query.isEmpty &&
      uri.fragment.isEmpty &&
      origins.any((origin) => origin.origin == uri.origin);
}

abstract interface class ReleaseSignatureVerifier {
  Future<bool> verifyEd25519({
    required Uint8List publicKey,
    required Uint8List canonicalManifest,
    required Uint8List signature,
  });
}

/// The only path allowed to install a peer-announced update. The adapter must
/// obtain the artifact from [release.manifest.artifactUri], verify its exact
/// byte count and SHA-256, and then use the official OS store/package installer
/// with platform signature/notarization checks. It never accepts peer bytes.
abstract interface class OfficialPlatformReleaseInstaller {
  Future<void> install(VerifiedOfficialRelease release);
}

final class VerifiedOfficialRelease {
  VerifiedOfficialRelease._({
    required this.manifest,
    required this.releaseKeyId,
  });

  final SignedUpdateManifest manifest;
  final String releaseKeyId;

  @override
  String toString() =>
      'VerifiedOfficialRelease(version: ${manifest.version}, '
      'counter: ${manifest.antiRollbackCounter}, '
      'artifact: [official/redacted])';
}

enum PeerUpdateRejection {
  wrongApplication,
  wrongPlatform,
  channelMismatch,
  rollbackOrSameCounter,
  releaseKeyMismatch,
  unofficialArtifactOrigin,
  artifactSizeRejected,
  futureManifest,
  signatureRejected,
}

final class PeerUpdateCheckResult {
  const PeerUpdateCheckResult._({this.release, this.rejection});
  factory PeerUpdateCheckResult.accepted(VerifiedOfficialRelease release) =>
      PeerUpdateCheckResult._(release: release);
  const factory PeerUpdateCheckResult.rejected(PeerUpdateRejection rejection) =
      _RejectedPeerUpdateCheckResult;

  final VerifiedOfficialRelease? release;
  final PeerUpdateRejection? rejection;
  bool get accepted => release != null && rejection == null;
}

final class _RejectedPeerUpdateCheckResult extends PeerUpdateCheckResult {
  const _RejectedPeerUpdateCheckResult(PeerUpdateRejection rejection)
    : super._(rejection: rejection);
}

final class PeerUpdateCoordinator {
  const PeerUpdateCoordinator({
    required this.installed,
    required this.releaseKey,
    required this.originPolicy,
    required this.signatureVerifier,
    required this.installer,
    this.maximumArtifactBytes = 500 * 1024 * 1024,
  });

  final InstalledApplication installed;
  final PinnedReleaseSigningKey releaseKey;
  final OfficialReleaseOriginPolicy originPolicy;
  final ReleaseSignatureVerifier signatureVerifier;
  final OfficialPlatformReleaseInstaller installer;
  final int maximumArtifactBytes;

  Future<PeerUpdateCheckResult> verifyManifest(
    SignedUpdateManifest manifest, {
    required DateTime now,
  }) async {
    if (manifest.appId != HhmApplicationId.flutter ||
        manifest.appId != installed.appId) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.wrongApplication,
      );
    }
    if (manifest.platform != installed.platform) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.wrongPlatform,
      );
    }
    if (manifest.channel != installed.channel) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.channelMismatch,
      );
    }
    if (manifest.antiRollbackCounter <= installed.antiRollbackCounter) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.rollbackOrSameCounter,
      );
    }
    if (manifest.signingKeyId != releaseKey.keyId) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.releaseKeyMismatch,
      );
    }
    if (!originPolicy.allows(manifest.artifactUri)) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.unofficialArtifactOrigin,
      );
    }
    if (manifest.artifactSize <= 0 ||
        manifest.artifactSize > maximumArtifactBytes) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.artifactSizeRejected,
      );
    }
    if (manifest.publishedAt.isAfter(now)) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.futureManifest,
      );
    }

    var signatureValid = false;
    try {
      signatureValid = await signatureVerifier.verifyEd25519(
        publicKey: releaseKey.publicKey,
        canonicalManifest: manifest.canonicalUnsignedBytes,
        signature: _decodeBase64Url(manifest.signature),
      );
    } on Object {
      signatureValid = false;
    }
    if (!signatureValid) {
      return const PeerUpdateCheckResult.rejected(
        PeerUpdateRejection.signatureRejected,
      );
    }
    return PeerUpdateCheckResult.accepted(
      VerifiedOfficialRelease._(
        manifest: manifest,
        releaseKeyId: releaseKey.keyId,
      ),
    );
  }

  Future<void> install(VerifiedOfficialRelease release) =>
      installer.install(release);
}

Uint8List _decodeBase64Url(String value) {
  try {
    return Uint8List.fromList(base64Url.decode(base64Url.normalize(value)));
  } on FormatException {
    throw const FormatException('Signature is not valid base64url');
  }
}
