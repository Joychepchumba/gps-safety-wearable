import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/theme_controller.dart';
import '../../../models/emergency_contact_model.dart';
import '../controllers/contacts_controller.dart';

class ContactsScreen extends StatelessWidget {
  const ContactsScreen({super.key});

  void _callNumber(String phone) async {
    final uri = Uri.parse('tel:${phone.replaceAll(' ', '')}');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      }
    } catch (_) {}
  }

  void _showAddEditSheet(BuildContext context, ContactsController controller, {EmergencyContactModel? contact}) {
    final isEditing = contact != null;
    final nameController = TextEditingController(text: contact?.contactName ?? '');
    final phoneController = TextEditingController(text: contact?.phoneNumber ?? '');
    final emailController = TextEditingController(text: contact?.email ?? '');
    final formKey = GlobalKey<FormState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
              ),
              decoration: BoxDecoration(
                color: ctx.cardBg,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 28),
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 44,
                          height: 4,
                          decoration: BoxDecoration(
                            color: ctx.cardBorder,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              isEditing ? Icons.edit_rounded : Icons.person_add_rounded,
                              color: AppColors.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              isEditing ? 'Edit Emergency Contact' : 'Add Emergency Contact',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: ctx.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'This contact will receive instant SMS alerts and live 3D Mapbox tracking links during SOS.',
                        style: TextStyle(fontSize: 13, color: ctx.textSecondary, height: 1.3),
                      ),
                      const SizedBox(height: 18),

                      // Name
                      Text('Contact Name', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: nameController,
                        style: TextStyle(fontSize: 15, color: ctx.textPrimary),
                        validator: (v) => (v == null || v.trim().isEmpty) ? 'Please enter a name' : null,
                        decoration: InputDecoration(
                          hintText: 'e.g. Mom, Primary Guardian, Dad',
                          hintStyle: TextStyle(color: ctx.textMuted),
                          prefixIcon: Icon(Icons.person_outline_rounded, color: ctx.textSecondary, size: 20),
                          filled: true,
                          fillColor: ctx.inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ctx.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ctx.cardBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Phone
                      Text('Phone Number', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: phoneController,
                        keyboardType: TextInputType.phone,
                        style: TextStyle(fontSize: 15, color: ctx.textPrimary),
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'Please enter a phone number';
                          if (v.trim().length < 8) return 'Enter a valid phone number';
                          return null;
                        },
                        decoration: InputDecoration(
                          hintText: '+254 700 000 000',
                          hintStyle: TextStyle(color: ctx.textMuted),
                          prefixIcon: Icon(Icons.phone_outlined, color: ctx.textSecondary, size: 20),
                          filled: true,
                          fillColor: ctx.inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ctx.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ctx.cardBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Email
                      Text('Email Address (Optional)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: ctx.textPrimary)),
                      const SizedBox(height: 6),
                      TextFormField(
                        controller: emailController,
                        keyboardType: TextInputType.emailAddress,
                        style: TextStyle(fontSize: 15, color: ctx.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'guardian@example.com',
                          hintStyle: TextStyle(color: ctx.textMuted),
                          prefixIcon: Icon(Icons.email_outlined, color: ctx.textSecondary, size: 20),
                          filled: true,
                          fillColor: ctx.inputBg,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ctx.cardBorder)),
                          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: ctx.cardBorder)),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: AppColors.primary, width: 1.5)),
                        ),
                      ),
                      const SizedBox(height: 22),

                      ElevatedButton(
                        onPressed: () async {
                          if (!formKey.currentState!.validate()) return;
                          final name = nameController.text.trim();
                          final phone = phoneController.text.trim();
                          final email = emailController.text.trim();

                          Navigator.pop(ctx);
                          try {
                            if (isEditing) {
                              await controller.updateContact(
                                id: contact.id,
                                name: name,
                                phone: phone,
                                email: email.isNotEmpty ? email : null,
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Updated $name successfully!'), backgroundColor: AppColors.success),
                                );
                              }
                            } else {
                              await controller.addContact(name, phone, email.isNotEmpty ? email : null);
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text('Added $name successfully!'), backgroundColor: AppColors.success),
                                );
                              }
                            }
                          } catch (e) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Notice: $e'), backgroundColor: AppColors.error),
                              );
                            }
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          padding: const EdgeInsets.symmetric(vertical: 15),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          elevation: 0,
                        ),
                        child: Text(
                          isEditing ? 'Save Changes' : 'Add Guardian Contact',
                          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _confirmDelete(BuildContext context, ContactsController controller, EmergencyContactModel contact) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: ctx.cardBg,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('Remove Contact', style: TextStyle(fontWeight: FontWeight.w800, color: ctx.textPrimary)),
        content: Text(
          'Are you sure you want to remove ${contact.contactName} (${contact.phoneNumber}) from your emergency contacts?',
          style: TextStyle(color: ctx.textSecondary, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: TextStyle(color: ctx.textSecondary, fontWeight: FontWeight.bold)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              controller.deleteContact(contact.id);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Removed ${contact.contactName}'), backgroundColor: AppColors.sosRed),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.sosRed,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              elevation: 0,
            ),
            child: const Text('Remove', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return 'G';
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
  }

  List<Color> _getGradient(int index) {
    const gradients = [
      [Color(0xFF0066FF), Color(0xFF00C6FF)],
      [Color(0xFF6366F1), Color(0xFF8B5CF6)],
      [Color(0xFF0D9488), Color(0xFF10B981)],
    ];
    return gradients[index % gradients.length];
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<ContactsController>();
    final count = controller.contacts.length;

    return Scaffold(
      backgroundColor: context.scaffoldBg,
      appBar: AppBar(
        backgroundColor: context.scaffoldBg,
        elevation: 0.5,
        title: Text(
          'Emergency Contacts',
          style: TextStyle(
            color: context.textPrimary,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: context.textPrimary, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: controller.isLoading && controller.contacts.isEmpty
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : RefreshIndicator(
              onRefresh: controller.loadContacts,
              color: AppColors.primary,
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: [
                  // Top Status Card
                  Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          AppColors.primary.withValues(alpha: 0.08),
                          AppColors.accent.withValues(alpha: 0.04),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: AppColors.primary.withValues(alpha: 0.2)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(Icons.shield_rounded, color: Colors.white, size: 24),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$count of 3 Guardians Added',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w800,
                                        color: context.textPrimary,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: count > 0 ? AppColors.success.withValues(alpha: 0.15) : AppColors.warning.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      count > 0 ? 'ARMED' : 'SETUP REQUIRED',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: count > 0 ? AppColors.success : AppColors.warning,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'During an emergency, SIM800L sends automated SMS alerts and call dispatch directly to these numbers.',
                                style: TextStyle(fontSize: 12, color: context.textSecondary, height: 1.3),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Section Header
                  const Text(
                    'TRUSTED GUARDIANS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.0,
                      color: AppColors.textMuted,
                    ),
                  ),
                  const SizedBox(height: 12),

                  if (controller.contacts.isEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 20),
                      decoration: BoxDecoration(
                        color: context.cardBg,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: context.cardBorder),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: context.surfaceBg,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.contact_phone_outlined, size: 36, color: context.textSecondary),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No Emergency Contacts Yet',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: context.textPrimary),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Add up to 3 trusted contacts who should receive your live coordinates and distress alerts.',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 13, color: context.textSecondary),
                          ),
                          const SizedBox(height: 20),
                          ElevatedButton.icon(
                            onPressed: () => _showAddEditSheet(context, controller),
                            icon: const Icon(Icons.add_rounded, color: Colors.white),
                            label: const Text('Add First Guardian', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    ...List.generate(controller.contacts.length, (index) {
                      final contact = controller.contacts[index];
                      final isPrimary = index == 0;
                      final gradient = _getGradient(index);

                      return Container(
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: context.cardBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isPrimary ? AppColors.primary.withValues(alpha: 0.3) : context.cardBorder,
                            width: isPrimary ? 1.5 : 1.0,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: context.isDarkMode ? Colors.black.withValues(alpha: 0.2) : Colors.black.withValues(alpha: 0.03),
                              blurRadius: 10,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                // Gradient Avatar with Initials
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: gradient,
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                    ),
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: gradient.first.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Center(
                                    child: Text(
                                      _getInitials(contact.contactName),
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 16,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 14),

                                // Name & Phone
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Flexible(
                                            child: Text(
                                              contact.contactName,
                                              style: TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.w800,
                                                color: context.textPrimary,
                                              ),
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                          if (isPrimary) ...[
                                            const SizedBox(width: 6),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary.withValues(alpha: 0.12),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text(
                                                'PRIMARY',
                                                style: TextStyle(
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                      const SizedBox(height: 3),
                                      Text(
                                        contact.phoneNumber,
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: context.textSecondary,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      if (contact.email != null && contact.email!.isNotEmpty) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          contact.email!,
                                          style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Divider(color: context.cardBorder, height: 1),
                            const SizedBox(height: 10),

                            // Action Buttons Row (Call, Edit, Delete)
                            Row(
                              children: [
                                // Call Button
                                OutlinedButton.icon(
                                  onPressed: () => _callNumber(contact.phoneNumber),
                                  icon: const Icon(Icons.phone_in_talk_rounded, size: 15, color: AppColors.success),
                                  label: const Text('Call', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.success)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.success),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    minimumSize: const Size(0, 32),
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // Edit Button
                                OutlinedButton.icon(
                                  onPressed: () => _showAddEditSheet(context, controller, contact: contact),
                                  icon: const Icon(Icons.edit_rounded, size: 15, color: AppColors.primary),
                                  label: const Text('Edit', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primary)),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: AppColors.primary),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                    minimumSize: const Size(0, 32),
                                  ),
                                ),
                                const Spacer(),

                                // Delete Button
                                IconButton(
                                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.sosRed, size: 20),
                                  onPressed: () => _confirmDelete(context, controller, contact),
                                  tooltip: 'Delete Contact',
                                  constraints: const BoxConstraints(),
                                  padding: const EdgeInsets.all(8),
                                ),
                              ],
                            ),
                          ],
                        ),
                      );
                    }),

                  const SizedBox(height: 80),
                ],
              ),
            ),
      floatingActionButton: count < 3
          ? FloatingActionButton.extended(
              backgroundColor: AppColors.primary,
              onPressed: () => _showAddEditSheet(context, controller),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(
                'Add Guardian ($count/3)',
                style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.white),
              ),
            )
          : null,
    );
  }
}
