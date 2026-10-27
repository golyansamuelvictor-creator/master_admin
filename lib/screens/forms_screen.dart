import 'package:flutter/material.dart';
import 'package:master_admin/screens/forms_studio.dart';

/// Forms / Surveys from the dashboard: each person's own forms, like
/// Google Forms (build, publish, collect answers). Kept apart from the
/// administration surveys on the Home › Survey tab.
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
  Widget build(BuildContext context) => const FormsHub(kind: 'personal');
}
