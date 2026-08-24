import 'dart:convert';
import 'dart:typed_data';

import 'peer_session.dart';

enum PeerPayloadType {
  residentMessage('hhm.resident-message.v1'),
  contactCard('hhm.contact-card.v1'),
  fileManifest('hhm.file-manifest.v1'),
  updateManifest('hhm.update-manifest.v1'),
  receipt('hhm.receipt.v1');

  const PeerPayloadType(this.wireName);
  final String wireName;
}

PeerPayloadType parsePeerPayloadType(String value) => switch (value) {
  'hhm.resident-message.v1' => PeerPayloadType.residentMessage,
  'hhm.contact-card.v1' => PeerPayloadType.contactCard,
  'hhm.file-manifest.v1' => PeerPayloadType.fileManifest,
  'hhm.update-manifest.v1' => PeerPayloadType.updateManifest,
  'hhm.receipt.v1' => PeerPayloadType.receipt,
  _ => throw const FormatException(
    'Payload type is not canonical or allowlisted',
  ),
};

/// Flutter v1 is intentionally narrower than the canonical interface. Signed
/// update manifests are enabled by their negotiated capability. Closed JSON
/// records additionally require an explicit local, foreground sharing choice;
/// their flags default off even when a session negotiated the capability.
/// Presence, door operations, raw conversation/audio, camera/location data,
/// arbitrary JSON, file chunks, scripts, and executables remain prohibited.
final class HhmFlutterPeerPayloadPolicy {
  const HhmFlutterPeerPayloadPolicy({
    this.allowResidentMessages = false,
    this.allowContactCards = false,
    this.allowReceipts = false,
  });

  final bool allowResidentMessages;
  final bool allowContactCards;
  final bool allowReceipts;

  bool allows(PeerPayloadType type, AuthenticatedPeerSession session) =>
      switch (type) {
        PeerPayloadType.updateManifest => session.capabilities.contains(
          PeerCapability.updateManifest,
        ),
        PeerPayloadType.residentMessage =>
          allowResidentMessages &&
              session.capabilities.contains(PeerCapability.residentMessage),
        PeerPayloadType.contactCard =>
          allowContactCards &&
              session.capabilities.contains(PeerCapability.contactCard),
        PeerPayloadType.receipt =>
          allowReceipts &&
              (session.capabilities.contains(PeerCapability.residentMessage) ||
                  session.capabilities.contains(PeerCapability.contactCard)),
        PeerPayloadType.fileManifest => false,
      };
}

enum HhmApplicationId {
  flutter('hhm-flutter'),
  desktopRust('hhm-desktop-app.rs');

  const HhmApplicationId(this.wireName);
  final String wireName;
}

enum HhmReleasePlatform { android, ios, linux, macos, windows, web }

enum HhmReleaseChannel { stable, beta }

/// Exact `SignedUpdateManifest` from hhm-interfaces commit ffc1df71.
final class SignedUpdateManifest {
  SignedUpdateManifest({
    required this.appId,
    required this.platform,
    required this.channel,
    required this.version,
    required this.antiRollbackCounter,
    required this.artifactSize,
    required this.artifactSha256,
    required this.artifactUri,
    required this.signingKeyId,
    required this.signature,
    required this.publishedAt,
  }) {
    if (version.length > 64 ||
        !RegExp(
          r'^[0-9]+\.[0-9]+\.[0-9]+(?:-[0-9A-Za-z.-]+)?$',
        ).hasMatch(version) ||
        antiRollbackCounter < 1 ||
        antiRollbackCounter > 9007199254740991 ||
        artifactSize < 1 ||
        artifactSize > 2147483648 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(artifactSha256) ||
        artifactUri.scheme != 'https' ||
        !artifactUri.hasAuthority ||
        artifactUri.userInfo.isNotEmpty ||
        artifactUri.toString().length > 2048 ||
        !RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(signingKeyId) ||
        signature.length < 64 ||
        signature.length > 512 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(signature)) {
      throw const FormatException('Signed update manifest fields are invalid');
    }
  }

  factory SignedUpdateManifest.fromJson(Map<String, Object?> json) {
    _requireExactKeys(json, const <String>{
      'schema',
      'app_id',
      'platform',
      'channel',
      'version',
      'anti_rollback_counter',
      'artifact_size',
      'artifact_sha256',
      'artifact_url',
      'signing_key_id',
      'signature',
      'published_at',
    });
    if (json['schema'] != PeerPayloadType.updateManifest.wireName) {
      throw const FormatException('Unsupported update manifest schema');
    }
    final counter = json['anti_rollback_counter'];
    final artifactSize = json['artifact_size'];
    if (counter is! int || artifactSize is! int) {
      throw const FormatException('Manifest counters must be integers');
    }
    return SignedUpdateManifest(
      appId: _parseApplicationId(_string(json, 'app_id')),
      platform: _parsePlatform(_string(json, 'platform')),
      channel: _parseChannel(_string(json, 'channel')),
      version: _string(json, 'version'),
      antiRollbackCounter: counter,
      artifactSize: artifactSize,
      artifactSha256: _string(json, 'artifact_sha256'),
      artifactUri: Uri.parse(_string(json, 'artifact_url')),
      signingKeyId: _string(json, 'signing_key_id'),
      signature: _string(json, 'signature'),
      publishedAt: _instant(json, 'published_at'),
    );
  }

  final HhmApplicationId appId;
  final HhmReleasePlatform platform;
  final HhmReleaseChannel channel;
  final String version;
  final int antiRollbackCounter;
  final int artifactSize;
  final String artifactSha256;
  final Uri artifactUri;
  final String signingKeyId;
  final String signature;
  final DateTime publishedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'schema': PeerPayloadType.updateManifest.wireName,
    'app_id': appId.wireName,
    'platform': platform.name,
    'channel': channel.name,
    'version': version,
    'anti_rollback_counter': antiRollbackCounter,
    'artifact_size': artifactSize,
    'artifact_sha256': artifactSha256,
    'artifact_url': artifactUri.toString(),
    'signing_key_id': signingKeyId,
    'signature': signature,
    'published_at': publishedAt.toUtc().toIso8601String(),
  };

  /// Deterministic Flutter/Rust interop bytes signed by the release key. The
  /// `signature` field is excluded; all other fields retain schema order.
  Uint8List get canonicalUnsignedBytes => Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'schema': PeerPayloadType.updateManifest.wireName,
        'app_id': appId.wireName,
        'platform': platform.name,
        'channel': channel.name,
        'version': version,
        'anti_rollback_counter': antiRollbackCounter,
        'artifact_size': artifactSize,
        'artifact_sha256': artifactSha256,
        'artifact_url': artifactUri.toString(),
        'signing_key_id': signingKeyId,
        'published_at': publishedAt.toUtc().toIso8601String(),
      }),
    ),
  );

  @override
  String toString() =>
      'SignedUpdateManifest(version: $version, counter: $antiRollbackCounter, '
      'artifact/signature: [redacted])';
}

final class PeerPayloadCodec {
  const PeerPayloadCodec();

  static const int maximumUpdateManifestBytes = 8192;

  Uint8List encodeUpdateManifest(SignedUpdateManifest manifest) {
    final bytes = Uint8List.fromList(
      utf8.encode(jsonEncode(manifest.toJson())),
    );
    if (bytes.isEmpty || bytes.length > maximumUpdateManifestBytes) {
      throw const FormatException(
        'Update manifest exceeds its strict size limit',
      );
    }
    return bytes;
  }

  SignedUpdateManifest decodeUpdateManifest(Uint8List plaintext) {
    if (plaintext.isEmpty || plaintext.length > maximumUpdateManifestBytes) {
      throw const FormatException('Update manifest plaintext size is invalid');
    }
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(plaintext, allowMalformed: false));
    } on Object {
      throw const FormatException('Update manifest is not strict UTF-8 JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Update manifest must be a JSON object');
    }
    return SignedUpdateManifest.fromJson(decoded);
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

HhmApplicationId _parseApplicationId(String value) => switch (value) {
  'hhm-flutter' => HhmApplicationId.flutter,
  'hhm-desktop-app.rs' => HhmApplicationId.desktopRust,
  _ => throw const FormatException('Unknown HHM application ID'),
};

HhmReleasePlatform _parsePlatform(String value) => switch (value) {
  'android' => HhmReleasePlatform.android,
  'ios' => HhmReleasePlatform.ios,
  'linux' => HhmReleasePlatform.linux,
  'macos' => HhmReleasePlatform.macos,
  'windows' => HhmReleasePlatform.windows,
  'web' => HhmReleasePlatform.web,
  _ => throw const FormatException('Unknown release platform'),
};

HhmReleaseChannel _parseChannel(String value) => switch (value) {
  'stable' => HhmReleaseChannel.stable,
  'beta' => HhmReleaseChannel.beta,
  _ => throw const FormatException('Unknown release channel'),
};
