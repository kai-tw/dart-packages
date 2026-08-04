/// Field-level, last-writer-wins sync over any passive blob store, ordered by
/// hybrid logical clocks.
///
/// The store is assumed to be dumb: it holds bytes at paths and does nothing
/// else. No server, no live peer connection, no code generation. Implement
/// [CloudStorage] over whatever you have — Google Drive's app data folder, an
/// object store, a directory — and [MirrorStore] over whatever your app
/// already persists in.
///
/// The three pieces you supply:
///
/// * [CloudStorage] — moves bytes to and from the shared store.
/// * [MirrorStore] — remembers what each record looked like the last time
///   both sides agreed, which is what makes a three-way merge possible.
/// * [SyncableSource] — reads and writes your own rows, one per record type.
///
/// Then [SyncEngine.syncAll] runs a round.
library;

export 'src/errors.dart';
export 'src/hlc/field_hlcs.dart';
export 'src/hlc/hlc.dart';
export 'src/hlc/hlc_clock.dart';
export 'src/hlc/hlc_dto.dart';
export 'src/sync/cloud/cloud_auth.dart';
export 'src/sync/cloud/cloud_availability.dart';
export 'src/sync/cloud/cloud_storage.dart';
export 'src/sync/cloud/in_memory_cloud_storage.dart';
export 'src/sync/field_divergence.dart';
export 'src/sync/in_memory_mirror_store.dart';
export 'src/sync/mirror_store.dart';
export 'src/sync/record_resolution.dart';
export 'src/sync/sync_engine.dart';
export 'src/sync/sync_entity_presence.dart';
export 'src/sync/sync_record.dart';
export 'src/sync/sync_serialization.dart';
