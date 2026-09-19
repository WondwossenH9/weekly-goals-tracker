import "package:flutter/material.dart";

import "../../../core/week_utils.dart";
import "../../../data/local/database.dart";

/// One day-of-week chip for a single goal. Tapping cycles
/// Not Done -> Ongoing -> Done -> Not Done. Sized generously (44x44
/// minimum) so it is comfortable to tap one-handed on a phone.
class TodoTile extends StatelessWidget {
  const TodoTile({
    super.key,
    required this.dayOfWeek,
    required this.todo,
    required this.onTap,
  });

  final int dayOfWeek;
  final TodoItem? todo;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final state = todo?.state ?? TodoState.notDone;

    final (Color bg, Color fg, IconData icon) = switch (state) {
      TodoState.done => (scheme.primary, scheme.onPrimary, Icons.check),
      TodoState.ongoing => (
          scheme.tertiaryContainer,
          scheme.onTertiaryContainer,
          Icons.autorenew,
        ),
      TodoState.notDone => (
          scheme.surfaceContainerHighest,
          scheme.onSurfaceVariant,
          Icons.close,
        ),
    };

    return Semantics(
      button: true,
      label: "${WeekUtils.dayLabel(dayOfWeek)}: ${state.name}",
      child: InkWell(
        onTap: todo == null ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 44,
          height: 52,
          decoration: BoxDecoration(
            color: todo == null ? scheme.surfaceContainerLow : bg,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                WeekUtils.dayLabel(dayOfWeek),
                style: TextStyle(
                  fontSize: 10,
                  color: todo == null ? scheme.outline : fg.withOpacity(0.8),
                ),
              ),
              const SizedBox(height: 2),
              Icon(
                todo == null ? Icons.remove : icon,
                size: 16,
                color: todo == null ? scheme.outline : fg,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
