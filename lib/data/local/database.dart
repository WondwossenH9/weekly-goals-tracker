import "dart:io";

import "package:drift/drift.dart";
import "package:drift/native.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

import "tables.dart";
// Re-exported (not just imported) so that any file importing database.dart
// also gets TodoState — drift regenerates fresh classes for every *table*
// (Week, Goal, TodoItem, ...) directly inside database.g.dart, so those are
// already visible to importers of this file, but a plain Dart enum like
// TodoState is never touched by the generator and stays wherever it was
// declared unless explicitly re-exported here.
export "tables.dart" show TodoState;

part "database.g.dart";

/// The local SQLite database — this is the source of truth on-device.
/// The Supabase copy is a mirror that [SyncService] keeps eventually
/// consistent with this one.
@DriftDatabase(tables: [
  Weeks,
  Goals,
  Todos,
  RecurrenceTemplates,
  SyncMeta,
  NotificationSettings,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());

  // Bump this whenever a table shape changes, and add a migration step
  // below — never edit an already-shipped schemaVersion in place.
  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await _ensureWeeksStartDateUnique();
          await _seedSingletonRows();
        },
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v2 added the local-only notification_settings table.
            await m.createTable(notificationSettings);
            await into(notificationSettings).insert(
              const NotificationSettingsCompanion(id: Value(0)),
              mode: InsertMode.insertOrIgnore,
            );
          }
          if (from < 3) {
            // v3: enforce one Week row per calendar week at the DB level.
            // Without this, a startup race (RecurrenceEngine's initial
            // populate call and a very-early AppLifecycleState.resumed
            // callback both calling getOrCreateWeek before either's
            // insert lands) could create two rows for the same
            // start_date, and every later lookup-by-date would throw
            // "too many elements". This does NOT deduplicate any rows
            // that already exist from before this fix — see the README
            // note about clearing local dev data after upgrading to v3.
            await _ensureWeeksStartDateUnique();
          }
        },
      );

  Future<void> _ensureWeeksStartDateUnique() {
    return customStatement(
      "CREATE UNIQUE INDEX IF NOT EXISTS weeks_start_date_unique "
      "ON weeks (start_date);",
    );
  }

  Future<void> _seedSingletonRows() async {
    await into(syncMeta).insert(
      const SyncMetaCompanion(id: Value(0)),
      mode: InsertMode.insertOrIgnore,
    );
    await into(notificationSettings).insert(
      const NotificationSettingsCompanion(id: Value(0)),
      mode: InsertMode.insertOrIgnore,
    );
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    // ApplicationSupport (not ApplicationDocuments) is the correct home for
    // a private sqlite file on desktop: Documents resolves to the user's
    // actual, visible ~/Documents folder on Linux/macOS/Windows, which is
    // the wrong place to silently drop an app-internal database file.
    final dbFolder = await getApplicationSupportDirectory();
    final file = File(p.join(dbFolder.path, "weekly_goals_tracker.sqlite"));
    return NativeDatabase.createInBackground(file);
  });
}
