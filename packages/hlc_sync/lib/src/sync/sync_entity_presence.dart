/// Whether one side of a sync knows about a record, and in what state.
///
/// Three states, not two. "Not present" is ambiguous on its own: a side that
/// deleted a record and a side that has never heard of it look identical if
/// all you can say is "absent", and treating them the same is what resurrects
/// deleted records.
///
/// Named [untracked] rather than `never` to avoid colliding with Dart's
/// `Never` type when reading or grepping.
enum SyncEntityPresence {
  /// A live record on this side.
  present,

  /// A tombstone: this side had the record and deleted it. The row is kept so
  /// the deletion can propagate.
  deleted,

  /// No record at all — neither live nor tombstoned. Usually "this device has
  /// never received this id".
  untracked,
}
