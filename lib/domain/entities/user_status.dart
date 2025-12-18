class UserStatus {
  final bool termsAccepted;
  final DateTime createdAt;
  final DateTime lastUpdated;

  UserStatus({
    required this.termsAccepted,
    required this.createdAt,
    required this.lastUpdated,
  });

  UserStatus copyWith({
    bool? termsAccepted,
    DateTime? createdAt,
    DateTime? lastUpdated,
  }) {
    return UserStatus(
      termsAccepted: termsAccepted ?? this.termsAccepted,
      createdAt: createdAt ?? this.createdAt,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
