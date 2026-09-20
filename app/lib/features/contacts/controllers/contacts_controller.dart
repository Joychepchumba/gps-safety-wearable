import 'package:flutter/material.dart';
import '../../../models/emergency_contact_model.dart';
import '../../../core/services/supabase_service.dart';
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
      if (user == null) return;

      final data = await _supabaseService.client
          .from('emergency_contacts')
          .select()
          .eq('user_id', user.id);

      contacts = (data as List).map((e) => EmergencyContactModel.fromJson(e)).toList();
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

      final newContact = {
        'user_id': user.id,
        'contact_name': name,
        'phone_number': phone,
        'email': email,
        'consent_status': 'pending',
      };

      await _supabaseService.client.from('emergency_contacts').insert(newContact);
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
      await _supabaseService.client.from('emergency_contacts').delete().eq('id', id);
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
