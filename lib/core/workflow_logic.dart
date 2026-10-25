class TransferWorkflow {
  // Define the levels in order
  static const List<String> approvalChain = [
    'TEAM_LEAD',
    'DEPT_LEVEL',
    'SUB_LOC_LEVEL',
    'LOC_LEVEL',
    'INTERNAL_AFFAIRS'
  ];

  // Logic to determine if a level is fully signed
  // (e.g. Dept needs BOTH Leader and Secretary)
  static bool isLevelComplete(String level, List<String> currentSignatures) {
    switch (level) {
      case 'TEAM_LEAD':
        return currentSignatures.contains('team_leader');
      // Secretaries are stored as dept_sec / sub_loc_sec / loc_sec in app_roles.
      // (The old names dept_secretary etc. don't exist, so these levels never completed.)
      case 'DEPT_LEVEL':
        return currentSignatures.contains('dept_leader') &&
               (currentSignatures.contains('dept_sec') || currentSignatures.contains('dept_secretary'));
      case 'SUB_LOC_LEVEL':
        return currentSignatures.contains('sub_loc_leader') &&
               (currentSignatures.contains('sub_loc_sec') || currentSignatures.contains('sub_loc_secretary'));
      case 'LOC_LEVEL':
        return currentSignatures.contains('loc_leader') &&
               (currentSignatures.contains('loc_sec') || currentSignatures.contains('loc_secretary'));
      case 'INTERNAL_AFFAIRS':
        return currentSignatures.contains('internal_affairs_dept_sec');
      default:
        return false;
    }
  }

  // Get the next level in the chain
  static String? getNextLevel(String currentLevel) {
    int currentIndex = approvalChain.indexOf(currentLevel);
    if (currentIndex != -1 && currentIndex < approvalChain.length - 1) {
      return approvalChain[currentIndex + 1];
    }
    return null; // No more levels (Final)
  }
  // Maps a specific role to the level they are authorized to sign for
  static String? getRoleLevel(String role) {
    if (role == 'team_leader') return 'TEAM_LEAD';
    if (role == 'dept_leader' || role == 'dept_sec' || role == 'dept_secretary') return 'DEPT_LEVEL';
    if (role == 'sub_loc_leader' || role == 'sub_loc_sec' || role == 'sub_loc_secretary') return 'SUB_LOC_LEVEL';
    if (role == 'loc_leader' || role == 'loc_sec' || role == 'loc_secretary') return 'LOC_LEVEL';
    if (role == 'internal_affairs_dept_sec') return 'INTERNAL_AFFAIRS';
    return null;
  }
}