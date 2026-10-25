import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../models/emergency_contact_model.dart';
import '../../../core/services/supabase_service.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/di/service_locator.dart';

class ContactsController extends ChangeNotifier {
  List<EmergencyContactModel> contacts = [];
  bool isLoading = false;
  
  final SupabaseService _supabaseService = sl<SupabaseService>();
  static const String _cachedContactsKey = 'cached_emergency_contacts';

  ContactsController() {
    _loadCachedContacts();
    loadContacts();
  }

  Future<void> _loadCachedContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString(_cachedContactsKey);
      if (cachedJson != null && cachedJson.isNotEmpty) {
        final List list = jsonDecode(cachedJson);
        contacts = list.map((e) => EmergencyContactModel.fromJson(e)).toList();
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> _saveCachedContacts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(contacts.map((e) => e.toJson()).toList());
      await prefs.setString(_cachedContactsKey, encoded);
    } catch (_) {}
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

        final loaded = (data as List).map((e) => EmergencyContactModel.fromJson(e)).toList();
        if (loaded.isNotEmpty) {
          contacts = loaded;
          await _saveCachedContacts();
          isLoading = false;
          notifyListeners();
          return;
        }
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
          final loaded = list.map((e) => EmergencyContactModel.fromJson(e)).toList();
          if (loaded.isNotEmpty) {
            contacts = loaded;
            await _saveCachedContacts();
          }
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
        'consent_status': 'accepted',
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
          }
        } catch (bkErr) {
          debugPrint('[CONTACTS] Backend API save notice: $bkErr');
        }
      }

      // 3. Guaranteed Local Save (ensure user always sees their contact instantly)
      final localContact = EmergencyContactModel(
        id: 'contact_${DateTime.now().millisecondsSinceEpoch}',
        userId: user.id,
        contactName: name.trim(),
        phoneNumber: phone.trim(),
        email: cleanEmail,
        consentStatus: 'accepted',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );

      // Check if already in list
      final existingIdx = contacts.indexWhere((c) => c.phoneNumber == phone.trim());
      if (existingIdx >= 0) {
        contacts[existingIdx] = localContact;
      } else {
        contacts.add(localContact);
      }
      await _saveCachedContacts();
      notifyListeners();

      // Refresh in background if saved remotely
      if (saved) {
        unawaited(loadContacts());
      }
    } catch (e) {
      debugPrint('Error adding contact: $e');
      rethrow;
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> updateContact({
    required String id,
    required String name,
    required String phone,
    String? email,
  }) async {
    isLoading = true;
    notifyListeners();

    try {
      final user = _supabaseService.client.auth.currentUser;
      final cleanEmail = (email != null && email.trim().isNotEmpty) ? email.trim() : null;
      final updateData = {
        'contact_name': name.trim(),
        'phone_number': phone.trim(),
        'email': cleanEmail,
      };

      bool saved = false;
      // 1. Try Supabase direct update
      try {
        await _supabaseService.client
            .from('emergency_contacts')
            .update(updateData)
            .eq('id', id);
        saved = true;
        debugPrint('[CONTACTS] Successfully updated via Supabase direct');
      } catch (e) {
        debugPrint('[CONTACTS] Supabase update notice: $e');
      }

      // 2. Fallback backend update
      if (!saved && user != null) {
        try {
          final backendBase = await AppConstants.getEffectiveBackendUrl();
          final uri = Uri.parse('$backendBase/users/contacts/$id');
          await http.put(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'ngrok-skip-browser-warning': 'true',
            },
            body: jsonEncode(updateData),
          );
        } catch (_) {}
      }

      // 3. Update in local cache
      final idx = contacts.indexWhere((c) => c.id == id);
      if (idx >= 0) {
        final old = contacts[idx];
        contacts[idx] = EmergencyContactModel(
          id: old.id,
          userId: old.userId,
          contactName: name.trim(),
          phoneNumber: phone.trim(),
          email: cleanEmail,
          consentStatus: old.consentStatus,
          createdAt: old.createdAt,
          updatedAt: DateTime.now(),
        );
        await _saveCachedContacts();
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error updating contact: $e');
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

      contacts.removeWhere((c) => c.id == id);
      await _saveCachedContacts();
      notifyListeners();

      unawaited(loadContacts());
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

