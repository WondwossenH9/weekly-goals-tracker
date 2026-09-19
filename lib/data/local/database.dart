import "dart:io";

import "package:drift/drift.dart";
import "package:drift/native.dart";
import "package:path/path.dart" as p;
import "package:path_provider/path_provider.dart";

import "tables.dart";

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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
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
        },
      );

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
    final dbFolder = await getApplicationDocumentsDirectory();
    final file = File(p.join(dbFolder.path, "weekly_goals_tracker.sqlite"));
    return NativeDatabase.createInBackground(file);
  });
}
