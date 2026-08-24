import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/visitors/visitor_qr.dart';

void main() {
  final issuedAt = DateTime.utc(2026, 8, 24, 12);

  RotatingVisitorQr qr({Duration lifetime = const Duration(minutes: 1)}) =>
      RotatingVisitorQr(
        opaquePayload: 'signed.opaque.payload',
        action: VisitorAction.signIn,
        doorId: 'front-door',
        nonce: '0123456789abcdef',
        keyId: 'visitor-key-2026-08',
        issuedAt: issuedAt,
        expiresAt: issuedAt.add(lifetime),
      );

  test('is displayable only inside its backend-issued minute window', () {
    final pass = qr();
    expect(pass.isDisplayableAt(issuedAt), isTrue);
    expect(
      pass.isDisplayableAt(issuedAt.add(const Duration(seconds: 59))),
      isTrue,
    );
    expect(
      pass.isDisplayableAt(issuedAt.add(const Duration(minutes: 1))),
      isFalse,
    );
  });

  test('rejects an overlong QR window', () {
    expect(
      () => qr(lifetime: const Duration(seconds: 91)),
      throwsFormatException,
    );
  });

  test('diagnostics redact payload and door identifiers', () {
    final text = qr().toString();
    expect(text, contains('payload: [redacted]'));
    expect(text, isNot(contains('signed.opaque.payload')));
    expect(text, isNot(contains('front-door')));
  });

  test('only server accepted status is accepted', () {
    final redemption = VisitorRedemption(
      eventId: 'event-redacted-in-logs',
      status: VisitorRedemptionStatus.alreadyUsed,
      recordedAt: issuedAt,
    );
    expect(redemption.accepted, isFalse);
  });
}
