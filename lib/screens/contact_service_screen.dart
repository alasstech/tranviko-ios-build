import 'package:flutter/material.dart';

import '../l10n/app_text.dart';
import '../services/api_service.dart';
import '../utils/call_id.dart';
import '../widgets/app_toast.dart';
import '../widgets/tranviko_validation_motion.dart';
import 'audio_call_screen.dart';

class ContactServiceScreen extends StatefulWidget {
  const ContactServiceScreen({super.key});

  @override
  State<ContactServiceScreen> createState() => _ContactServiceScreenState();
}

class _ContactServiceScreenState extends State<ContactServiceScreen> {
  final _formKey = GlobalKey<FormState>();
  final _validationMotion = TranvikoValidationController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _subjectController = TextEditingController();
  final _messageController = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    final user = ApiService.currentUser;
    final agent = ApiService.currentAgent;
    _nameController.text =
        (user?['fullName'] ?? agent?['name'] ?? agent?['fullName'] ?? '')
            .toString();
    _emailController.text = (user?['email'] ?? agent?['email'] ?? '')
        .toString();
    _phoneController.text = (user?['phone'] ?? agent?['phone'] ?? '')
        .toString();
    _subjectController.text = appT('assistance');
  }

  @override
  void dispose() {
    _validationMotion.dispose();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _subjectController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage() async {
    if (!validateTranvikoForm(context, _formKey, _validationMotion)) {
      return;
    }
    setState(() => _sending = true);
    try {
      final result = await ApiService.sendContactServiceMessage(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        phone: _phoneController.text.trim(),
        subject: _subjectController.text.trim(),
        message: _messageController.text.trim(),
      );
      if (!mounted) return;
      AppToast.show(
        context,
        result['message']?.toString() ?? 'Message envoye.',
        tone: AppToastTone.success,
      );
      _messageController.clear();
    } catch (error) {
      if (!mounted) return;
      AppToast.show(
        context,
        AppToast.friendlyError(error),
        tone: AppToastTone.error,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _startServiceCall() {
    final callId = newCallId();
    Navigator.push(
      context,
      MaterialPageRoute(
        settings: RouteSettings(name: AudioCallScreen.routeNameFor(callId)),
        builder: (_) => AudioCallScreen(
          title: 'Service client',
          serviceCall: true,
          initialCallId: callId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(appTC(context, 'assistance'))),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          FilledButton.icon(
            onPressed: _startServiceCall,
            icon: const Icon(Icons.call),
            label: Text(appTC(context, 'supportCall')),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appTC(context, 'contactDetails'),
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  _ContactRow(
                    icon: Icons.place,
                    label: appTC(context, 'address'),
                    value: 'Gare principale, Bamako, Mali',
                  ),
                  _ContactRow(
                    icon: Icons.email,
                    label: appTC(context, 'email'),
                    value: 'support@alass-tech.click',
                  ),
                  _ContactRow(
                    icon: Icons.phone,
                    label: appTC(context, 'phone'),
                    value: '+223 00 00 00 00',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: TranvikoValidationMotion(
                controller: _validationMotion,
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appTC(context, 'sendMessageTitle'),
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _nameController,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'fullName'),
                          prefixIcon: const Icon(Icons.person),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? appTC(context, 'nameRequired')
                            : null,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'email'),
                          prefixIcon: const Icon(Icons.alternate_email),
                        ),
                        validator: (value) {
                          final text = value?.trim() ?? '';
                          if (text.isEmpty)
                            return appTC(context, 'emailRequired');
                          if (!text.contains('@'))
                            return appTC(context, 'invalidEmail');
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'phone'),
                          prefixIcon: const Icon(Icons.phone),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _subjectController,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'subject'),
                          prefixIcon: const Icon(Icons.subject),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _messageController,
                        minLines: 4,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: appTC(context, 'message'),
                          prefixIcon: const Icon(Icons.message),
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? appTC(context, 'messageRequired')
                            : null,
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _sending ? null : _sendMessage,
                        icon: _sending
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.send),
                        label: Text(
                          _sending
                              ? appTC(context, 'sending')
                              : appTC(context, 'sendMessageAction'),
                        ),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _ContactRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 2),
                Text(value),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
