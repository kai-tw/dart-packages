/// Who the cloud storage belongs to.
///
/// The account *is* the backend — there is no server of ours behind it, and
/// no user record anywhere. Signing in buys exactly one thing: somewhere to
/// put the files.
abstract class CloudAuth {
  /// Emits whenever sign-in state changes.
  ///
  /// Starts unseeded: consumers must treat "nothing yet" as different from
  /// "signed out". Seeding it with `false` would make a cold start look like
  /// a deliberate sign-out and could trigger a sign-out cleanup — which
  /// clears the sync base — before the platform has even answered.
  Stream<bool> get isSignedIn;

  /// Whether a session is currently known to be active.
  Future<bool> currentlySignedIn();

  /// Opens the provider's sign-in flow.
  ///
  /// Returns false when the user cancelled. Cancelling is an ordinary outcome,
  /// not a failure, and must not surface as an error.
  Future<bool> signIn();

  Future<void> signOut();

  /// A stable, non-reversible marker for the connected account, or null when
  /// there is none.
  ///
  /// Exists so the app can notice it is now talking to a *different* account.
  /// Deliberately not the account id or the email: nothing here needs to know
  /// who the user is, only whether they changed, and the value is persisted —
  /// privacy.md keeps identifiers out of SharedPreferences.
  Future<String?> accountFingerprint();
}
