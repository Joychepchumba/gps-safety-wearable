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

  static String normalizePhoneNumber(String raw) {
    String cleaned = raw.replaceAll(RegExp(r'[\s\-()]'), '');
    if (cleaned.startsWith('0')) {
      return '+254${cleaned.substring(1)}';
    } else if (cleaned.startsWith('254') && !cleaned.startsWith('+')) {
      return '+$cleaned';
    } else if (!cleaned.startsWith('+')) {
      return '+254$cleaned';
    }
    return cleaned;
  }

  Future<void> addContact(
    String name,
    String phone,
    String? email, {
    String? relationship,
  }) async {
    if (contacts.length >= 3) {
      throw Exception('Maximum 3 emergency contacts allowed.');
    }

    final trimmedName = name.trim();
    if (trimmedName.isEmpty) {
      throw Exception('Please provide a contact name.');
    }

    final normalizedPhone = normalizePhoneNumber(phone.trim());
    if (normalizedPhone.length < 10) {
      throw Exception('Please provide a valid phone number.');
    }

    // Check if phone number is already registered in local list
    final alreadyExists = contacts.any(
      (c) => c.phoneNumber.replaceAll(RegExp(r'[\s\-]'), '') == normalizedPhone,
    );
    if (alreadyExists) {
      throw Exception('$normalizedPhone is already in your emergency contacts.');
    }

    isLoading = true;
    notifyListeners();

    try {
      final user = _supabaseService.client.auth.currentUser;
      if (user == null) throw Exception('Not logged in. Please sign in again.');
      final userId = user.id;

      // Format contact name with relationship if provided
      String displayName = trimmedName;
      if (relationship != null &&
          relationship.isNotEmpty &&
          relationship != 'Other' &&
          !displayName.toLowerCase().contains(relationship.toLowerCase())) {
        displayName = '$trimmedName ($relationship)';
      }

      final cleanEmail = (email != null && email.trim().isNotEmpty) ? email.trim() : null;
      final newContact = {
        'user_id': userId,
        'contact_name': displayName,
        'phone_number': normalizedPhone,
        'email': cleanEmail,
        'consent_status': 'pending',
      };

      // Ensure user profile exists in public.users to satisfy foreign key constraint
      try {
        await _supabaseService.client.from('users').upsert({
          'id': userId,
          'full_name': user.userMetadata?['full_name'] ?? 'SafeLink User',
          'phone_number': user.userMetadata?['phone'] ?? '',
          'email': user.email,
        }, onConflict: 'id');
      } catch (sbUserErr) {
        debugPrint('[CONTACTS] Ensure public.users entry notice: $sbUserErr');
      }

      bool saved = false;
      String? lastError;

      // 1. Try Supabase direct insert
      try {
        await _supabaseService.client.from('emergency_contacts').insert(newContact);
        saved = true;
        debugPrint('[CONTACTS] Successfully inserted via Supabase direct');
      } catch (sbError) {
        lastError = sbError.toString();
        debugPrint('[CONTACTS] Supabase direct insert notice ($sbError), attempting backend fallback...');
      }

      // 2. Fallback to backend API
      if (!saved) {
        try {
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
            final errBody = jsonDecode(res.body);
            final detail = errBody['detail'] ?? res.body;
            throw Exception(detail);
          }
        } catch (apiErr) {
          debugPrint('[CONTACTS] Backend API insert failed: $apiErr');
          lastError = apiErr.toString();
        }
      }

      if (!saved) {
        throw Exception(
          lastError?.contains('already registered') == true
              ? 'This phone number is already registered.'
              : 'Could not save emergency contact. Please check your network and try again.',
        );
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

