class UserModel {
  final String id;
  final String email;
  final String? fullName;
  final String userType;
  final String? phone;
  final String? avatarUrl;

  UserModel({
    required this.id,
    required this.email,
    this.fullName,
    required this.userType,
    this.phone,
    this.avatarUrl,
  });

  factory UserModel.fromMap(Map<String, dynamic> map) {
    return UserModel(
      id: map['id'] ?? '',
      email: map['email'] ?? '',
      fullName: map['full_name'],
      userType: map['user_type'] ?? 'member',
      phone: map['phone'],
      avatarUrl: map['avatar_url'],
    );
  }

  bool get isAdmin => userType == 'admin';
  bool get isCoach => userType == 'coach';
  bool get isAthlete => userType == 'athlete';
  bool get isMember => userType == 'member';
}
