/// Whether syncing can run at all right now.
enum CloudSyncAvailability {
  /// The user has not turned sync on. Not an error state.
  disabled,

  /// Sync is on but nobody is signed in.
  signedOut,

  /// Signed in and ready.
  ready,
}
