import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/local/database.dart";
import "../../providers/providers.dart";
import "../recurring/recurring_templates_screen.dart";

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
      appBar: AppBar(title: const Text("Settings")),
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
              onTap: () => ref.read(syncServiceProvider).sync(),
            ),
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
