/// Identity authorities that must both be represented in an HHM session.
enum IdentityAuthority { supabase, sharedAuth }

/// Authentication evidence returned by the HHM backend after token exchange.
final class AuthAssurance {
  AuthAssurance(Iterable<IdentityAuthority> authorities)
    : authorities = Set.unmodifiable(authorities);

  final Set<IdentityAuthority> authorities;

  bool get satisfiesDualAuth =>
      authorities.contains(IdentityAuthority.supabase) &&
      authorities.contains(IdentityAuthority.sharedAuth);
}

/// Non-secret session metadata exposed to UI state.
///
/// Bearer tokens and provider credentials deliberately do not appear here.
/// A platform implementation keeps them in protected storage and attaches them
/// only inside its transport layer.
final class AuthenticatedSession {
  AuthenticatedSession({required this.assurance, required this.expiresAt});

  final AuthAssurance assurance;
  final DateTime expiresAt;

  bool isUsableAt(DateTime now) =>
      assurance.satisfiesDualAuth && now.isBefore(expiresAt);

  @override
  String toString() =>
      'AuthenticatedSession(dualAuth: ${assurance.satisfiesDualAuth}, '
      'expiresAt: $expiresAt)';
}

/// A hosted authorization request prepared by the HHM backend.
///
/// The backend coordinates Supabase plus Shared Auth, validates the callback,
/// performs provider-token exchange, and returns an HHM-scoped session. The app
/// uses system browser / app-link APIs and must verify the request identifier.
final class AuthorizationLaunch {
  const AuthorizationLaunch({
    required this.authorizationUri,
    required this.requestId,
    required this.expiresAt,
  });

  final Uri authorizationUri;
  final String requestId;
  final DateTime expiresAt;
}

/// Platform adapter for dual authentication.
///
/// Implementations must use PKCE, protected platform storage, exact redirect
/// matching, and a system browser. They must not accept Bluetooth or proximity
/// evidence as an authentication factor.
abstract interface class AuthGateway {
  Future<AuthorizationLaunch> beginSignIn({required Uri returnUri});

  Future<AuthenticatedSession> completeSignIn({
    required Uri callbackUri,
    required String expectedRequestId,
  });

  Future<AuthenticatedSession?> restoreSession();

  Future<void> signOut({bool allDevices = false});
}
