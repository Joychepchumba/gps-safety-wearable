import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../models/emergency_contact_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';

class ContactsController extends ChangeNotifier {
  List<EmergencyContactModel> contacts = [];
  bool isLoading = false;
  
  final SupabaseService _supabaseService = sl<SupabaseService>();

  ContactsController() {
    loadContacts();
  }

  Future<void> loadContacts() async {
    isLoading = true;
    notifyListeners();

    try {
      final user = _supabaseService.client.auth.currentUser;
      if (user == null) {
        isLoading = false;
        notifyListeners();
        return;
      }

      // 1. Try Supabase direct select
      try {
        final data = await _supabaseService.client
            .from('emergency_contacts')
            .select()
            .eq('user_id', user.id);

        contacts = (data as List).map((e) => EmergencyContactModel.fromJson(e)).toList();
        isLoading = false;
        notifyListeners();
        return;
      } catch (sbError) {
        debugPrint('[CONTACTS] Supabase direct query notice: $sbError');
      }

      // 2. Fallback to FastAPI backend endpoint
      try {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final uri = Uri.parse('$backendBase/users/contacts?user_id=${user.id}');
        final res = await http.get(
          uri,
          headers: {'ngrok-skip-browser-warning': 'true'},
        ).timeout(const Duration(seconds: 6));

        if (res.statusCode == 200) {
          final decoded = jsonDecode(res.body);
          final list = decoded['data'] as List;
          contacts = list.map((e) => EmergencyContactModel.fromJson(e)).toList();
        }
      } catch (backendError) {
        debugPrint('[CONTACTS] Backend load notice: $backendError');
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> addContact(String name, String phone, String? email) async {
    if (contacts.length >= 3) {
      throw Exception('Maximum 3 contacts allowed');
    }

    isLoading = true;
    notifyListeners();

    try {
      final user = _supabaseService.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in');

      final cleanEmail = (email != null && email.trim().isNotEmpty) ? email.trim() : null;
      final newContact = {
        'user_id': user.id,
        'contact_name': name.trim(),
        'phone_number': phone.trim(),
        'email': cleanEmail,
        'consent_status': 'pending',
      };

      bool saved = false;

      // 1. Try Supabase direct insert
      try {
        await _supabaseService.client.from('emergency_contacts').insert(newContact);
        saved = true;
        debugPrint('[CONTACTS] Successfully inserted via Supabase direct');
      } catch (sbError) {
        debugPrint('[CONTACTS] Supabase direct insert notice ($sbError), attempting backend fallback...');
      }

      // 2. Fallback to backend API
      if (!saved) {
        final backendBase = await AppConstants.getEffectiveBackendUrl();
        final uri = Uri.parse('$backendBase/users/contacts');
        final res = await http.post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'ngrok-skip-browser-warning': 'true',
          },
          body: jsonEncode(newContact),
        ).timeout(const Duration(seconds: 8));

        if (res.statusCode >= 200 && res.statusCode < 300) {
          saved = true;
          debugPrint('[CONTACTS] Successfully saved via backend API');
        } else {
          throw Exception('Failed to add contact (${res.statusCode}): ${res.body}');
        }
      }

      await loadContacts();
    } catch (e) {
      debugPrint('Error adding contact: $e');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> deleteContact(String id) async {
    isLoading = true;
    notifyListeners();

    try {
      final user = _supabaseService.client.auth.currentUser;
      bool deleted = false;

      // 1. Try Supabase delete
      try {
        await _supabaseService.client.from('emergency_contacts').delete().eq('id', id);
        deleted = true;
      } catch (sbError) {
        debugPrint('[CONTACTS] Supabase delete notice: $sbError');
      }

      // 2. Fallback to backend delete
      if (!deleted && user != null) {
        try {
          final backendBase = await AppConstants.getEffectiveBackendUrl();
          final uri = Uri.parse('$backendBase/users/contacts/$id?user_id=${user.id}');
          await http.delete(uri, headers: {'ngrok-skip-browser-warning': 'true'});
        } catch (_) {}
      }

      await loadContacts();
    } catch (e) {
      debugPrint('Error deleting contact: $e');
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateConsent(String id, String status) async {
    try {
      await _supabaseService.client
          .from('emergency_contacts')
          .update({'consent_status': status})
          .eq('id', id);
      await loadContacts();
    } catch (e) {
      debugPrint('Error updating consent: $e');
    }
  }
}

