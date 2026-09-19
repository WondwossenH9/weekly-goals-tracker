import "dart:async";

import "package:flutter/material.dart";
import "package:flutter_riverpod/flutter_riverpod.dart";
import "package:intl/intl.dart";

import "../../data/local/database.dart";
import "../../providers/providers.dart";

/// Free-text reflection field, autosaved on a short debounce so the user
/// never has to hit an explicit "Save". Works the same for the current
/// week and for historical weeks opened from the history screen — editing
/// an old reflection just bumps its edit timestamp, per spec.
class ReflectionField extends ConsumerStatefulWidget {
  const ReflectionField({super.key, required this.week});
  final Week week;

  @override
  ConsumerState<ReflectionField> createState() => _ReflectionFieldState();
}

class _ReflectionFieldState extends ConsumerState<ReflectionField> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.week.reflectionText);
  // Tracked locally so the "last edited" label updates immediately after a
  // save, without depending on the parent provider re-fetching the row.
  late DateTime? _lastEdited = widget.week.reflectionUpdatedAt;
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 600), () async {
      await ref
          .read(weeksRepositoryProvider)
          .saveReflection(widget.week.id, value);
      if (mounted) setState(() => _lastEdited = DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          onChanged: _onChanged,
          maxLines: 6,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: "How did this week go?",
            border: OutlineInputBorder(),
          ),
        ),
        if (_lastEdited != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              "Last edited ${DateFormat.yMMMd().add_jm().format(_lastEdited!)}",
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
      ],
    );
  }
}
