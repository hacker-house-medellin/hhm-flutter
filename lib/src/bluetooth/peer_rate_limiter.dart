import 'dart:collection';

enum PeerRateCategory { handshake, encryptedEnvelope, updateAdvertisement }

final class PeerRateBudget {
  const PeerRateBudget({
    required this.maximumMessages,
    required this.maximumBytes,
    required this.maximumFrameBytes,
  });

  final int maximumMessages;
  final int maximumBytes;
  final int maximumFrameBytes;
}

final class PeerRateLimitPolicy {
  const PeerRateLimitPolicy({
    this.window = const Duration(minutes: 1),
    this.maximumTrackedScopes = 256,
    this.handshake = const PeerRateBudget(
      maximumMessages: 6,
      maximumBytes: 16 * 1024,
      maximumFrameBytes: 4096,
    ),
    this.encryptedEnvelope = const PeerRateBudget(
      maximumMessages: 30,
      maximumBytes: 128 * 1024,
      maximumFrameBytes: 16 * 1024,
    ),
    this.updateAdvertisement = const PeerRateBudget(
      maximumMessages: 4,
      maximumBytes: 16 * 1024,
      maximumFrameBytes: 4096,
    ),
  });

  final Duration window;
  final int maximumTrackedScopes;
  final PeerRateBudget handshake;
  final PeerRateBudget encryptedEnvelope;
  final PeerRateBudget updateAdvertisement;

  PeerRateBudget budgetFor(PeerRateCategory category) => switch (category) {
    PeerRateCategory.handshake => handshake,
    PeerRateCategory.encryptedEnvelope => encryptedEnvelope,
    PeerRateCategory.updateAdvertisement => updateAdvertisement,
  };
}

enum PeerRateDecision {
  accepted,
  invalidScope,
  invalidFrame,
  clockMovedBackwards,
  messageLimit,
  byteLimit,
  capacityExceeded,
}

final class _RateSample {
  const _RateSample(this.recordedAt, this.byteLength);

  final DateTime recordedAt;
  final int byteLength;
}

final class _RateWindow {
  final ListQueue<_RateSample> samples = ListQueue<_RateSample>();
  int totalBytes = 0;
  DateTime? lastSeenAt;
}

/// Bounded, fail-closed sliding-window limiter for pre-decryption BLE traffic.
///
/// [scope] is a rotating ephemeral discovery ID before authentication and a
/// random session ID afterward. It must never be a name, email, resident ID,
/// permanent hardware address, or token.
final class PeerRateLimiter {
  PeerRateLimiter({this.policy = const PeerRateLimitPolicy()});

  final PeerRateLimitPolicy policy;
  final Map<String, _RateWindow> _windows = <String, _RateWindow>{};

  PeerRateDecision tryConsume({
    required String scope,
    required PeerRateCategory category,
    required int byteLength,
    required DateTime now,
  }) {
    if (scope.length < 16 ||
        scope.length > 128 ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(scope)) {
      return PeerRateDecision.invalidScope;
    }
    final budget = policy.budgetFor(category);
    if (byteLength <= 0 || byteLength > budget.maximumFrameBytes) {
      return PeerRateDecision.invalidFrame;
    }

    _purge(now);
    final key = '${category.name}:$scope';
    var usage = _windows[key];
    if (usage == null) {
      if (_windows.length >= policy.maximumTrackedScopes) {
        return PeerRateDecision.capacityExceeded;
      }
      usage = _RateWindow();
      _windows[key] = usage;
    }
    final lastSeenAt = usage.lastSeenAt;
    if (lastSeenAt != null && now.isBefore(lastSeenAt)) {
      return PeerRateDecision.clockMovedBackwards;
    }
    if (usage.samples.length >= budget.maximumMessages) {
      return PeerRateDecision.messageLimit;
    }
    if (usage.totalBytes + byteLength > budget.maximumBytes) {
      return PeerRateDecision.byteLimit;
    }

    usage.samples.addLast(_RateSample(now, byteLength));
    usage.totalBytes += byteLength;
    usage.lastSeenAt = now;
    return PeerRateDecision.accepted;
  }

  void _purge(DateTime now) {
    final oldestAllowed = now.subtract(policy.window);
    _windows.removeWhere((_, usage) {
      while (usage.samples.isNotEmpty &&
          !usage.samples.first.recordedAt.isAfter(oldestAllowed)) {
        usage.totalBytes -= usage.samples.removeFirst().byteLength;
      }
      if (usage.samples.isEmpty) {
        usage.lastSeenAt = null;
        return true;
      }
      return false;
    });
  }
}
