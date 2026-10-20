import 'package:intl/intl.dart';

abstract final class FormatUtil {
  /// `2:14`, `48:12`, `1:32:05`.
  static String duration(int ms) {
    final total = ms ~/ 1000;
    final h = total ~/ 3600;
    final m = total ~/ 60 % 60;
    final s = (total % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$s' : '$m:$s';
  }

  /// `00:17:42` for transcript rows.
  static String clock(int ms) {
    final total = (ms < 0 ? 0 : ms) ~/ 1000;
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(total ~/ 3600)}:${two(total ~/ 60 % 60)}:${two(total % 60)}';
  }

  /// `57 MB`, `1.2 GB` (decimal units, as storage is marketed).
  static String bytes(int bytes) {
    if (bytes >= 1000 * 1000 * 1000) return '${(bytes / 1e9).toStringAsFixed(1)} GB';
    if (bytes >= 1000 * 1000) return '${(bytes / 1e6).round()} MB';
    if (bytes >= 1000) return '${(bytes / 1e3).round()} KB';
    return '$bytes B';
  }

  /// Installed memory as marketed: binary gigabytes, rounded ("18 GB").
  static String memory(int bytes) => '${(bytes / (1 << 30)).round()} GB';

  static String dateTime(DateTime value, String locale) => DateFormat.yMMMd(locale).add_Hm().format(value);
}
