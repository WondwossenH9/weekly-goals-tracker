import "package:intl/intl.dart";

/// Small set of helpers for working with ISO (Monday-start) weeks, since
/// almost every feature (weekly view, recurrence, sync) needs to agree on
/// what "the current week" means.
class WeekUtils {
  static final DateFormat _fmt = DateFormat("yyyy-MM-dd");

  /// The Monday of the week containing [date], as yyyy-MM-dd.
  static String mondayOf(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    return _fmt.format(DateTime(monday.year, monday.month, monday.day));
  }

  static String currentWeekStart() => mondayOf(DateTime.now());

  static DateTime parse(String yyyyMmDd) => _fmt.parse(yyyyMmDd);

  static String addWeeks(String yyyyMmDd, int weeks) {
    final d = parse(yyyyMmDd).add(Duration(days: 7 * weeks));
    return _fmt.format(d);
  }

  /// Whole weeks between two Monday-anchored week-start strings.
  static int weeksBetween(String fromYyyyMmDd, String toYyyyMmDd) {
    final diff = parse(toYyyyMmDd).difference(parse(fromYyyyMmDd)).inDays;
    return diff ~/ 7;
  }

  static String dayLabel(int isoWeekday) {
    const labels = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
    return labels[isoWeekday - 1];
  }
}
