enum UserRole {
  superAdmin('admin'),
  locationLeader('loc_leader'), 
  locationSec('loc_sec'),
  locationGenSec('loc_gen_sec'),
  teamLeader('team_leader'),
  cellLeader('cell_leader'),
  deptLeader('dept_leader'),
  unknown('unknown');

  final String key;
  const UserRole(this.key);

  static UserRole fromKey(String? key) {
    return UserRole.values.firstWhere(
      (e) => e.key == key,
      orElse: () => UserRole.unknown,
    );
  }
}