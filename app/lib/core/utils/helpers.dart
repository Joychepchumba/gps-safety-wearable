import 'dart:math';

class Helpers {
  static String formatPhone(String raw) {
    if (raw.contains(',')) {
      return raw
          .split(',')
          .map((p) => formatSinglePhone(p))
          .where((p) => p.isNotEmpty)
          .join(',');
    }
    return formatSinglePhone(raw);
  }

  static String formatSinglePhone(String raw) {
    String clean = raw.replaceAll(RegExp(r'[\s\-\(\)\.]'), '').trim();
    if (clean.isEmpty) return '';
    if (clean.startsWith('+')) {
      return clean;
    }
    if (clean.startsWith('0') && clean.length == 10) {
      return '+254${clean.substring(1)}';
    }
    if (clean.startsWith('254') && clean.length == 12) {
      return '+$clean';
    }
    if (clean.length == 9) {
      return '+254$clean';
    }
    return clean.startsWith('+') ? clean : '+$clean';
  }

  static String buildLocationUrl(double lat, double lng) {
    return 'https://maps.google.com/?q=$lat,$lng';
  }

  static String buildSmsMessage(String template, Map<String, String> values) {
    String msg = template;
    values.forEach((key, value) {
      msg = msg.replaceAll('{$key}', value);
    });
    return msg;
  }

  static double distanceMeters(double lat1, double lng1, double lat2, double lng2) {
    const double p = 0.017453292519943295; // Math.PI / 180
    final double a = 0.5 - cos((lat2 - lat1) * p)/2 + 
                     cos(lat1 * p) * cos(lat2 * p) * 
                     (1 - cos((lng2 - lng1) * p))/2;
    return 12742000 * asin(sqrt(a)); // 2 * R * 1000; R = 6371 km
  }

  static String timeAgo(DateTime dt) {
    Duration diff = DateTime.now().difference(dt);
    if (diff.inDays > 365) return '${(diff.inDays / 365).floor()} yrs ago';
    if (diff.inDays > 30) return '${(diff.inDays / 30).floor()} mos ago';
    if (diff.inDays > 0) return '${diff.inDays} d ago';
    if (diff.inHours > 0) return '${diff.inHours} hrs ago';
    if (diff.inMinutes > 0) return '${diff.inMinutes} min ago';
    return 'just now';
  }
}
