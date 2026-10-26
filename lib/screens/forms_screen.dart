import 'package:flutter/material.dart';
import 'package:master_admin/screens/forms_studio.dart';

/// "New form" from the home menu: opens the forms studio and asks for a
/// template straight away. (The old basic builder is replaced by
/// forms_studio.dart; forms made with it still open there.)
class FormsScreen extends StatelessWidget {
  final String title;
  final String userEmail;
  final String userRole;

  const FormsScreen({
    super.key,
    required this.title,
    required this.userEmail,
    required this.userRole,
  });

  @override
  Widget build(BuildContext context) => const FormsHub(startNew: true);
}
