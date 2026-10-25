import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../utils/helpers.dart';

class SmsService {
  String get _apiUrl {
    if (AppConstants.africasTalkingUsername == 'sandbox') {
      return 'https://api.sandbox.africastalking.com/version1/messaging';
    }
    return 'https://api.africastalking.com/version1/messaging';
  }

  Future<bool> sendSms(String to, String message) async {
    try {
      final formattedTo = Helpers.formatPhone(to);
      if (formattedTo.isEmpty) {
        debugPrint('[SMS] Aborting: empty recipient phone number');
        return false;
      }
      debugPrint('[SMS] Dispatching via Africa\'s Talking ($_apiUrl) to: $formattedTo');
      
      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {
          'apiKey': AppConstants.africasTalkingApiKey,
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'username': AppConstants.africasTalkingUsername,
          'to': formattedTo,
          'message': message,
        },
      ).timeout(const Duration(seconds: 12));

      debugPrint('[SMS] Africa\'s Talking status ${response.statusCode}: ${response.body}');
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      debugPrint('[SMS ERROR] Failed to send SMS via Africa\'s Talking: $e');
      return false;
    }
  }

  Future<Map<String, bool>> sendBulkSms(List<String> recipients, String message) async {
    final Map<String, bool> results = {};
    final validRecipients = recipients
        .map((p) => Helpers.formatPhone(p))
        .where((p) => p.isNotEmpty && !p.startsWith('+254800') && p.length >= 10)
        .toSet()
        .toList();

    if (validRecipients.isEmpty) {
      debugPrint('[SMS] No valid mobile recipients provided for bulk SMS');
      return results;
    }

    // Attempt 1: Combined bulk send
    final toList = validRecipients.join(',');
    final success = await sendSms(toList, message);

    if (success) {
      for (String recipient in validRecipients) {
        results[recipient] = true;
      }
      return results;
    }

    // Attempt 2: Individual fallback (in case one carrier number caused the batch to fail)
    debugPrint('[SMS] Bulk send returned false, falling back to individual dispatches...');
    for (String recipient in validRecipients) {
      final ok = await sendSms(recipient, message);
      results[recipient] = ok;
    }
    return results;
  }

  Future<void> notifyEmergencyContacts(
    List<String> phones,
    String userName,
    double lat,
    double lng, {
    String? panicEventId,
  }) async {
    final baseUrl = await AppConstants.getEffectiveBackendUrl();
    final String trackUrl = (panicEventId != null && panicEventId.isNotEmpty)
        ? '$baseUrl/alert/track/$panicEventId'
        : '$baseUrl/alert/track/live?lat=$lat&lng=$lng&name=${Uri.encodeComponent(userName)}';

    final message = '🚨 EMERGENCY ALERT: $userName triggered an SOS panic alarm!\n'
        'Location: Lat ${lat.toStringAsFixed(5)}, Lng ${lng.toStringAsFixed(5)}\n'
        'Live 3D Tracking: $trackUrl';

    final allPhones = List<String>.from(phones);
    if (!allPhones.contains(AppConstants.policeNumber)) {
      allPhones.add(AppConstants.policeNumber);
    }
    await sendBulkSms(allPhones, message);
  }

  Future<void> notifyPolice(
    String userName,
    double lat,
    double lng, {
    String? panicEventId,
  }) async {
    final baseUrl = await AppConstants.getEffectiveBackendUrl();
    final String trackUrl = (panicEventId != null && panicEventId.isNotEmpty)
        ? '$baseUrl/alert/track/$panicEventId'
        : '$baseUrl/alert/track/live?lat=$lat&lng=$lng&name=${Uri.encodeComponent(userName)}';

    final message = '🚨 POLICE DISPATCH: $userName needs urgent assistance!\n'
        'Live 3D Tracking: $trackUrl';

    await sendSms(AppConstants.policeNumber, message);
  }

  Future<void> sendLiveLocationShareSms(
    List<String> phones,
    String userName,
    double lat,
    double lng,
    int hours,
    String sessionToken,
  ) async {
    final durationStr = hours >= 24 ? '24 hours' : '$hours hour${hours > 1 ? "s" : ""}';
    final liveMapboxLink = AppConstants.buildLiveTrackingUrl(
      lat: lat,
      lng: lng,
      name: userName,
      session: sessionToken,
    );

    final message = '📍 SafeGuard Live GPS: $userName is sharing live location with you for $durationStr.\n'
        'Live 3D Tracking: $liveMapboxLink';

    await sendBulkSms(phones, message);
  }
}
