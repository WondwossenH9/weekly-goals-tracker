import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";

import "../../data/local/database.dart";
import "../../providers/providers.dart";

/// Lists every recurrence template and lets the user create, edit,
/// pause (via the active switch), or delete one. Per spec, editing a
/// template only ever affects weeks generated *after* the edit — past
/// weeks' Goal rows are untouched, since they were already materialized
/// by RecurrenceEngine and only reference the template by id.
class RecurringTemplatesScreen extends ConsumerWidget {
  const RecurringTemplatesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final templatesAsync = ref.watch(recurrenceTemplatesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text("Recurring goals")),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text("$e")),
        data: (templates) {
          if (templates.isEmpty) {
            return const _EmptyState();
          }
          return ListView.builder(
            itemCount: templates.length,
            itemBuilder: (context, i) => _TemplateTile(template: templates[i]),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text("New recurring goal"),
        onPressed: () => _openEditor(context, ref),
      ),
    );
  }

  static Future<void> _openEditor(
    BuildContext context,
    WidgetRef ref, {
    RecurrenceTemplate? existing,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => _TemplateEditorSheet(existing: existing),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.repeat,
                size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text("No recurring goals yet",
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            const Text(
              "e.g. \u201cExercise\u201d, every week, Mon/Wed/Fri.",
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _TemplateTile extends ConsumerWidget {
  const _TemplateTile({required this.template});
  final RecurrenceTemplate template;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      title: Text(template.goalTitle),
      subtitle: Text(_describeRule(template)),
      onTap: () => RecurringTemplatesScreen._openEditor(context, ref,
          existing: template),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Switch(
            value: template.active,
            onChanged: (v) => ref
                .read(recurrenceTemplatesRepositoryProvider)
                .setActive(template.id, v),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete recurring goal?"),
        content: Text(
          "\u201c${template.goalTitle}\u201d will stop generating new weekly "
          "goals. Past weeks that already used it keep their history.",
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text("Cancel")),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text("Delete")),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(recurrenceTemplatesRepositoryProvider).delete(template.id);
    }
  }

  String _describeRule(RecurrenceTemplate t) {
    switch (t.rule) {
      case "weekly":
        return "Every week";
      case "biweekly":
        return "Every 2 weeks";
      case "custom":
        final days = (t.customDays ?? "")
            .split(",")
            .where((s) => s.trim().isNotEmpty)
            .map(int.parse)
            .map(_shortDayName)
            .join(", ");
        return days.isEmpty ? "Custom days" : days;
      default:
        return t.rule;
    }
  }

  String _shortDayName(int weekday) => const [
        "Mon",
        "Tue",
        "Wed",
        "Thu",
        "Fri",
        "Sat",
        "Sun",
      ][weekday - 1];
}

class _TemplateEditorSheet extends ConsumerStatefulWidget {
  const _TemplateEditorSheet({this.existing});
  final RecurrenceTemplate? existing;

  @override
  ConsumerState<_TemplateEditorSheet> createState() => _TemplateEditorSheetState();
}

class _TemplateEditorSheetState extends ConsumerState<_TemplateEditorSheet> {
  late final _titleController =
      TextEditingController(text: widget.existing?.goalTitle ?? "");
  late String _rule = widget.existing?.rule ?? "weekly";
  late final Set<int> _customDays = {
    ...?widget.existing?.customDays
        ?.split(",")
        .where((s) => s.trim().isNotEmpty)
        .map(int.parse),
  };

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.existing != null;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(isEditing ? "Edit recurring goal" : "New recurring goal",
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            autofocus: !isEditing,
            decoration: const InputDecoration(labelText: "Goal title"),
          ),
          const SizedBox(height: 16),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: "weekly", label: Text("Weekly")),
              ButtonSegment(value: "biweekly", label: Text("Biweekly")),
              ButtonSegment(value: "custom", label: Text("Custom days")),
            ],
            selected: {_rule},
            onSelectionChanged: (s) => setState(() => _rule = s.first),
          ),
          if (_rule == "custom") ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                for (var d = 1; d <= 7; d++)
                  FilterChip(
                    label: Text(_shortDayName(d)),
                    selected: _customDays.contains(d),
                    onSelected: (sel) => setState(() {
                      sel ? _customDays.add(d) : _customDays.remove(d);
                    }),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Cancel"),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _canSave() ? _save : null,
                child: Text(isEditing ? "Save" : "Create"),
              ),
            ],
          ),
        ],
      ),
    );
  }

  bool _canSave() {
    if (_titleController.text.trim().isEmpty) return false;
    if (_rule == "custom" && _customDays.isEmpty) return false;
    return true;
  }

  Future<void> _save() async {
    final repo = ref.read(recurrenceTemplatesRepositoryProvider);
    final title = _titleController.text.trim();
    final days = _rule == "custom" ? (_customDays.toList()..sort()) : null;

    if (widget.existing != null) {
      await repo.update(widget.existing!.id,
          goalTitle: title, rule: _rule, customDays: days);
    } else {
      await repo.create(goalTitle: title, rule: _rule, customDays: days);
      // Reflect the new template in the *current* week immediately, rather
      // than making the user wait for the next app restart to see it.
      await ref.read(recurrenceEngineProvider).ensureCurrentWeekIsPopulated();
    }

    if (mounted) Navigator.of(context).pop();
  }

  String _shortDayName(int weekday) => const [
        "Mon",
        "Tue",
        "Wed",
        "Thu",
        "Fri",
        "Sat",
        "Sun",
      ][weekday - 1];
}
