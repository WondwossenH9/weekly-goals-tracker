import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../core/week_utils.dart";
import "../../data/local/database.dart";
import "../../providers/providers.dart";
import "../recurring/recurring_templates_screen.dart";
import "../sync/sync_status_indicator.dart";

/// All three reminder toggles read from and write straight to the
/// persisted [NotificationSettingsRow] (see providers.dart) — nothing here
/// is held in local widget state, so preferences survive an app restart.
/// Every change also immediately reschedules the underlying OS
/// notification so the two never drift apart.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(notificationSettingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Settings"),
        actions: const [SyncStatusIndicator()],
      ),
      body: settingsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("Couldn\u2019t load settings: $e")),
        data: (settings) => ListView(
          children: [
            const _SectionHeader("Goals"),
            ListTile(
              leading: const Icon(Icons.repeat),
              title: const Text("Manage recurring goals"),
              subtitle: const Text("Edit or turn off recurring goal templates"),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const RecurringTemplatesScreen()),
              ),
            ),
            const Divider(),
            const _SectionHeader("Reminders"),
            _DailyNudgeTile(settings: settings),
            const Divider(),
            _WeeklyReflectionTile(settings: settings),
            const Divider(),
            _RecurringSetupTile(settings: settings),
            const Divider(),
            const _SectionHeader("Account"),
            ListTile(
              title: const Text("Sync now"),
              leading: const Icon(Icons.sync),
              onTap: () => triggerSync(ref),
            ),
            if (kDebugMode) ...[
              const Divider(),
              const _DevToolsSection(),
            ],
          ],
        ),
      ),
    );
  }
}

Future<void> _reschedule(WidgetRef ref) async {
  final settings = await ref.read(notificationSettingsRepositoryProvider).get();
  final service = await ref.read(notificationServiceProvider.future);
  await service.rescheduleFromSettings(settings);
}

class _DailyNudgeTile extends ConsumerWidget {
  const _DailyNudgeTile({required this.settings});
  final NotificationSettingsRow settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time =
        TimeOfDay(hour: settings.dailyNudgeHour, minute: settings.dailyNudgeMinute);
    return Column(
      children: [
        SwitchListTile(
          title: const Text("Daily todo nudge"),
          subtitle: Text(time.format(context)),
          value: settings.dailyNudgeEnabled,
          onChanged: (v) async {
            await ref
                .read(notificationSettingsRepositoryProvider)
                .updateDailyNudge(enabled: v);
            await _reschedule(ref);
          },
        ),
        if (settings.dailyNudgeEnabled)
          ListTile(
            title: const Text("Nudge time"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked == null) return;
              await ref
                  .read(notificationSettingsRepositoryProvider)
                  .updateDailyNudge(hour: picked.hour, minute: picked.minute);
              await _reschedule(ref);
            },
          ),
      ],
    );
  }
}

class _WeeklyReflectionTile extends ConsumerWidget {
  const _WeeklyReflectionTile({required this.settings});
  final NotificationSettingsRow settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time = TimeOfDay(
        hour: settings.reflectionHour, minute: settings.reflectionMinute);
    return Column(
      children: [
        SwitchListTile(
          title: const Text("End-of-week reflection prompt"),
          subtitle: Text(
              "${_weekdayName(settings.reflectionWeekday)} at ${time.format(context)}"),
          value: settings.weeklyReflectionEnabled,
          onChanged: (v) async {
            await ref
                .read(notificationSettingsRepositoryProvider)
                .updateWeeklyReflection(enabled: v);
            await _reschedule(ref);
          },
        ),
        if (settings.weeklyReflectionEnabled)
          ListTile(
            title: const Text("Day and time"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final weekday = await _pickWeekday(context, settings.reflectionWeekday);
              if (weekday == null) return;
              if (!context.mounted) return;
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked == null) return;
              await ref.read(notificationSettingsRepositoryProvider).updateWeeklyReflection(
                    weekday: weekday,
                    hour: picked.hour,
                    minute: picked.minute,
                  );
              await _reschedule(ref);
            },
          ),
      ],
    );
  }
}

class _RecurringSetupTile extends ConsumerWidget {
  const _RecurringSetupTile({required this.settings});
  final NotificationSettingsRow settings;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final time =
        TimeOfDay(hour: settings.recurringHour, minute: settings.recurringMinute);
    return Column(
      children: [
        SwitchListTile(
          title: const Text("New-week recurring goals reminder"),
          subtitle: Text(
              "${_weekdayName(settings.recurringWeekday)} at ${time.format(context)}"),
          value: settings.recurringSetupEnabled,
          onChanged: (v) async {
            await ref
                .read(notificationSettingsRepositoryProvider)
                .updateRecurringSetup(enabled: v);
            await _reschedule(ref);
          },
        ),
        if (settings.recurringSetupEnabled)
          ListTile(
            title: const Text("Day and time"),
            trailing: const Icon(Icons.chevron_right),
            onTap: () async {
              final weekday = await _pickWeekday(context, settings.recurringWeekday);
              if (weekday == null) return;
              if (!context.mounted) return;
              final picked = await showTimePicker(context: context, initialTime: time);
              if (picked == null) return;
              await ref.read(notificationSettingsRepositoryProvider).updateRecurringSetup(
                    weekday: weekday,
                    hour: picked.hour,
                    minute: picked.minute,
                  );
              await _reschedule(ref);
            },
          ),
      ],
    );
  }
}

Future<int?> _pickWeekday(BuildContext context, int current) {
  return showDialog<int>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text("Choose a day"),
      children: [
        for (var d = 1; d <= 7; d++)
          SimpleDialogOption(
            onPressed: () => Navigator.of(ctx).pop(d),
            child: Row(
              children: [
                if (d == current) const Icon(Icons.check, size: 18),
                if (d == current) const SizedBox(width: 8),
                Text(_weekdayName(d)),
              ],
            ),
          ),
      ],
    ),
  );
}

String _weekdayName(int weekday) => const [
      "Monday",
      "Tuesday",
      "Wednesday",
      "Thursday",
      "Friday",
      "Saturday",
      "Sunday",
    ][weekday - 1];

/// Debug-only (see the kDebugMode guard where this is used). Lets you
/// point the Week/Summary tabs at an arbitrary past or future week and
/// run the recurring-goals engine against it, so History and recurring
/// goals can be tested against real, varied data without touching the
/// system clock — this only changes which week the app's own state
/// considers "selected," never DateTime.now() itself.
class _DevToolsSection extends ConsumerWidget {
  const _DevToolsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedWeekStart = ref.watch(selectedWeekStartProvider);
    final isViewingToday = selectedWeekStart == WeekUtils.currentWeekStart();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader("Developer tools (debug builds only)"),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "For testing History and recurring goals against a week other "
            "than today, without changing your system clock.",
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        const SizedBox(height: 4),
        ListTile(
          leading: Icon(isViewingToday ? Icons.today : Icons.event_busy),
          title: Text(isViewingToday
              ? "Viewing: today's week"
              : "Viewing: week of $selectedWeekStart"),
          subtitle: isViewingToday
              ? null
              : const Text("Not your real current week \u2014 Week/Summary "
                  "tabs reflect this instead"),
        ),
        ListTile(
          leading: const Icon(Icons.date_range),
          title: const Text("Jump to a week"),
          subtitle: const Text("Pick any date; Week/Summary tabs follow it"),
          onTap: () => _jumpToWeek(ref, context),
        ),
        ListTile(
          leading: const Icon(Icons.auto_awesome),
          title: const Text("Populate recurring goals for viewed week"),
          subtitle: const Text(
              "Runs the exact logic that normally runs at a real week's start"),
          onTap: () async {
            await ref
                .read(recurrenceEngineProvider)
                .ensureWeekIsPopulated(selectedWeekStart);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                  content: Text("Recurring goals populated for viewed week")));
            }
          },
        ),
        if (!isViewingToday)
          ListTile(
            leading: const Icon(Icons.undo),
            title: const Text("Return to today"),
            onTap: () => ref.read(selectedWeekStartProvider.notifier).state =
                WeekUtils.currentWeekStart(),
          ),
      ],
    );
  }

  Future<void> _jumpToWeek(WidgetRef ref, BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDate: now,
    );
    if (picked == null) return;
    ref.read(selectedWeekStartProvider.notifier).state = WeekUtils.mondayOf(picked);
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(text,
          style: Theme.of(context)
              .textTheme
              .labelLarge
              ?.copyWith(color: Theme.of(context).colorScheme.primary)),
    );
  }
}
