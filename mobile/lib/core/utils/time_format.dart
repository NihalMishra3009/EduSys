class TimeFormat {
  static const Duration _istOffset = Duration(hours: 5, minutes: 30);

  static DateTime nowIst() => DateTime.now().toUtc().add(_istOffset);

  static DateTime toIst(DateTime input) {
    final utc = input.isUtc ? input : input.toUtc();
    return utc.add(_istOffset);
  }

  static DateTime? parseToIst(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return null;
    }
    try {
      final value = raw.trim();
      final parsed = DateTime.parse(value);
      final hasZone = value.endsWith("Z") || value.contains("+") || value.lastIndexOf("-") > 9;
      if (hasZone) {
        return toIst(parsed);
      }
      return DateTime.utc(
        parsed.year,
        parsed.month,
        parsed.day,
        parsed.hour,
        parsed.minute,
        parsed.second,
        parsed.millisecond,
        parsed.microsecond,
      ).add(_istOffset);
    } catch (_) {
      return null;
    }
  }

  static String formatMinutes12h(int minutes) {
    final total = minutes.clamp(0, 1439);
    var hour24 = total ~/ 60;
    final minute = total % 60;
    final isPm = hour24 >= 12;
    final suffix = isPm ? "PM" : "AM";
    if (hour24 == 0) {
      hour24 = 12;
    } else if (hour24 > 12) {
      hour24 -= 12;
    }
    final mm = minute.toString().padLeft(2, "0");
    return "$hour24:$mm $suffix";
  }

  static String formatDate(DateTime date) {
    final dd = date.day.toString().padLeft(2, "0");
    final mm = date.month.toString().padLeft(2, "0");
    return "$dd/$mm/${date.year}";
  }

  static String formatDateTime12hIst(DateTime date) {
    final mins = (date.hour * 60) + date.minute;
    return "${formatDate(date)} ${formatMinutes12h(mins)} IST";
  }
}
