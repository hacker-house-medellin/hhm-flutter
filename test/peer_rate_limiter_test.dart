import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_rate_limiter.dart';

void main() {
  final now = DateTime.utc(2026, 8, 24, 18);
  const scope = 'EphemeralScope_0123456789abcdef';

  PeerRateLimiter limiter({
    int maximumMessages = 2,
    int maximumBytes = 10,
    int maximumFrameBytes = 8,
    int maximumTrackedScopes = 8,
  }) => PeerRateLimiter(
    policy: PeerRateLimitPolicy(
      window: const Duration(minutes: 1),
      maximumTrackedScopes: maximumTrackedScopes,
      encryptedEnvelope: PeerRateBudget(
        maximumMessages: maximumMessages,
        maximumBytes: maximumBytes,
        maximumFrameBytes: maximumFrameBytes,
      ),
    ),
  );

  PeerRateDecision consume(
    PeerRateLimiter value, {
    String peerScope = scope,
    int bytes = 4,
    DateTime? at,
  }) => value.tryConsume(
    scope: peerScope,
    category: PeerRateCategory.encryptedEnvelope,
    byteLength: bytes,
    now: at ?? now,
  );

  test('enforces message and byte budgets independently', () {
    final messageLimited = limiter(maximumMessages: 1);
    expect(consume(messageLimited), PeerRateDecision.accepted);
    expect(consume(messageLimited), PeerRateDecision.messageLimit);

    final byteLimited = limiter(maximumMessages: 3, maximumBytes: 7);
    expect(consume(byteLimited, bytes: 4), PeerRateDecision.accepted);
    expect(consume(byteLimited, bytes: 4), PeerRateDecision.byteLimit);
  });

  test('rejects invalid scope and oversized frame before tracking', () {
    final value = limiter();
    expect(
      consume(value, peerScope: 'resident@example.com'),
      PeerRateDecision.invalidScope,
    );
    expect(consume(value, bytes: 9), PeerRateDecision.invalidFrame);
    expect(consume(value, bytes: 0), PeerRateDecision.invalidFrame);
  });

  test('window expiry permits a fresh bounded attempt', () {
    final value = limiter(maximumMessages: 1);
    expect(consume(value), PeerRateDecision.accepted);
    expect(consume(value), PeerRateDecision.messageLimit);
    expect(
      consume(value, at: now.add(const Duration(minutes: 1, seconds: 1))),
      PeerRateDecision.accepted,
    );
  });

  test('clock rollback and peer-scope exhaustion fail closed', () {
    final value = limiter(maximumTrackedScopes: 1);
    expect(consume(value), PeerRateDecision.accepted);
    expect(
      consume(value, at: now.subtract(const Duration(seconds: 1))),
      PeerRateDecision.clockMovedBackwards,
    );
    expect(
      consume(value, peerScope: 'OtherScope_0123456789abcdef'),
      PeerRateDecision.capacityExceeded,
    );
  });
}
