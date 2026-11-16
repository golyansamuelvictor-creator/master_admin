import 'package:flutter/material.dart';

import '../admin_user_management_screen.dart';

/// Account approvals now live in User management (one screen for approving,
/// rejecting, changing roles and removing users). Kept so older links open
/// the same place, on the Pending list.
class AccountApprovalsScreen extends StatelessWidget {
  const AccountApprovalsScreen({super.key});
  @override
  Widget build(BuildContext context) => const AdminUserManagementScreen(initialStatus: 'pending');
}
