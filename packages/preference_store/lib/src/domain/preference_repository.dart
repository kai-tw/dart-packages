/// A typed, observable seam over one persisted preference shape.
///
/// Implementations own the mapping between [T] and whatever primitives
/// [PreferenceLocalDataSource] can store — this interface says nothing
/// about *how* a value is encoded, only that reading, writing, resetting
/// and observing it all go through one contract.
abstract class PreferenceRepository<T> {
  /// Emits the latest value after every successful [savePreference].
  ///
  /// A fresh subscriber gets no replay of the current value — call
  /// [getPreference] for that. Broadcast, not single-subscription: more
  /// than one consumer may watch the same preference at once.
  Stream<T> get onChangeStream;

  Future<T> getPreference();

  Future<void> savePreference(T data);

  Future<void> resetPreference();
}
