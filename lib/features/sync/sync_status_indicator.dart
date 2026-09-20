import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/remote/sync_service.dart";
import "../../providers/providers.dart";

/// The spec's "☁️ synced / ⏳ pending / ⚠️ conflict" indicator. Meant to be
/// dropped into any screen's AppBar actions — cheap to do since it reads
/// from shared providers rather than taking any per-screen state.
///
/// Until a real Supabase project is configured and someone's signed in,
/// SyncService.sync() always returns SyncStatus.idle (there's no account
/// to sync against yet), so this will just show the "synced" cloud rather
/// than anything alarming — that's the correct, honest state for
/// local-only usage, not a bug.
class SyncStatusIndicator extends ConsumerWidget {
  const SyncStatusIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(syncStatusProvider);
    final hasPending = ref.watch(hasPendingChangesProvider).valueOrNull ?? false;

    if (status == SyncStatus.syncing) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final (IconData icon, String tooltip) = switch (status) {
      SyncStatus.error => (Icons.sync_problem, "Sync failed \u2014 tap to retry"),
      SyncStatus.conflict => (Icons.sync_problem, "Sync conflict \u2014 tap to retry"),
      _ => hasPending
          ? (Icons.cloud_upload_outlined, "Changes waiting to sync \u2014 tap to sync now")
          : (Icons.cloud_done_outlined, "Synced"),
    };

    return IconButton(
      icon: Icon(icon),
      tooltip: tooltip,
      onPressed: () => triggerSync(ref),
    );
  }
}
