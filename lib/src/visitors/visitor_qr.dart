enum VisitorAction { signIn, signOut }

/// A short-lived, backend-signed QR envelope.
///
/// [opaquePayload] is displayed or submitted verbatim. The client never parses
/// its claims to authorize access and never mints a replacement locally.
final class RotatingVisitorQr {
  RotatingVisitorQr({
    required this.opaquePayload,
    required this.action,
    required this.doorId,
    required this.nonce,
    required this.keyId,
    required this.issuedAt,
    required this.expiresAt,
  }) {
    if (opaquePayload.isEmpty || nonce.length < 16 || keyId.isEmpty) {
      throw const FormatException('QR envelope is missing signed metadata');
    }
    final lifetime = expiresAt.difference(issuedAt);
    if (lifetime <= Duration.zero || lifetime > const Duration(seconds: 90)) {
      throw const FormatException(
        'Rotating visitor QR lifetime must be between 1 and 90 seconds',
      );
    }
  }

  final String opaquePayload;
  final VisitorAction action;
  final String doorId;
  final String nonce;
  final String keyId;
  final DateTime issuedAt;
  final DateTime expiresAt;

  bool isDisplayableAt(DateTime now) =>
      !now.isBefore(issuedAt) && now.isBefore(expiresAt);

  Duration remainingAt(DateTime now) {
    if (!isDisplayableAt(now)) {
      return Duration.zero;
    }
    return expiresAt.difference(now);
  }

  @override
  String toString() =>
      'RotatingVisitorQr(action: $action, doorId: [redacted], '
      'expiresAt: $expiresAt, payload: [redacted])';
}

/// One-time backend challenge bound to a scan attempt.
final class VisitorScanChallenge {
  const VisitorScanChallenge({
    required this.challengeId,
    required this.nonce,
    required this.expiresAt,
  });

  final String challengeId;
  final String nonce;
  final DateTime expiresAt;

  bool isUsableAt(DateTime now) => now.isBefore(expiresAt);
}

enum VisitorRedemptionStatus { accepted, rejected, alreadyUsed, expired }

/// Server-authoritative outcome. A client never converts a local scan into an
/// accepted sign-in or sign-out without this acknowledgement.
final class VisitorRedemption {
  const VisitorRedemption({
    required this.eventId,
    required this.status,
    required this.recordedAt,
  });

  final String eventId;
  final VisitorRedemptionStatus status;
  final DateTime recordedAt;

  bool get accepted => status == VisitorRedemptionStatus.accepted;
}

/// Transport contract for the HHM rotating visitor QR API.
///
/// Implementations attach dual-auth credentials inside the transport layer,
/// request a fresh QR for every minute window, use a cryptographically random
/// [clientNonce] for redemption, and never retry an ambiguous accepted write.
abstract interface class VisitorQrGateway {
  Future<RotatingVisitorQr> fetchQr({
    required VisitorAction action,
    required String doorId,
  });

  Future<VisitorScanChallenge> beginRedemption({required String doorId});

  Future<VisitorRedemption> redeem({
    required String opaquePayload,
    required VisitorScanChallenge challenge,
    required String clientNonce,
  });
}
