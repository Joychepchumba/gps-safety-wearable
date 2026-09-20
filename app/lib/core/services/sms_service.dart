import 'package:http/http.dart' as http;
import '../constants/app_constants.dart';
import '../constants/app_strings.dart';
import '../utils/helpers.dart';

class SmsService {
  Future<bool> sendSms(String to, String message) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.africastalking.com/version1/messaging'),
        headers: {
          'apiKey': AppConstants.africasTalkingApiKey,
          'Accept': 'application/json',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'username': AppConstants.africasTalkingUsername,
          'to': to,
          'message': message,
        }
      );
      return response.statusCode == 200 || response.statusCode == 201;
    } catch (e) {
      return false;
    }
  }

  Future<Map<String, bool>> sendBulkSms(List<String> recipients, String message) async {
    final Map<String, bool> results = {};
    String toList = recipients.join(',');
    bool success = await sendSms(toList, message);
    for (String recipient in recipients) {
      results[recipient] = success;
    }
    return results;
  }

  Future<void> notifyEmergencyContacts(List<String> phones, String userName, double lat, double lng) async {
    String url = Helpers.buildLocationUrl(lat, lng);
    String message = Helpers.buildSmsMessage(AppStrings.smsTemplateEmergency, {
      'name': userName,
      'location_url': url,
      'time': DateTime.now().toString(),
    });
    List<String> allPhones = List.from(phones);
    allPhones.add(AppConstants.policeNumber);
    await sendBulkSms(allPhones, message);
  }

  Future<void> notifyPolice(String userName, double lat, double lng) async {
    String url = Helpers.buildLocationUrl(lat, lng);
    String message = 'EMERGENCY: $userName needs help at $url';
    await sendSms(AppConstants.policeNumber, message);
  }
}
