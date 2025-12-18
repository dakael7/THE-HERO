class Verification {
  final String apiRefId; 
  final DateTime lastCheck;

  Verification({
    required this.apiRefId,
    required this.lastCheck,
  });

  bool get isRecent {
    final difference = DateTime.now().difference(lastCheck);
    return difference.inDays < 30; 
  }

  Verification copyWith({
    String? apiRefId,
    DateTime? lastCheck,
  }) {
    return Verification(
      apiRefId: apiRefId ?? this.apiRefId,
      lastCheck: lastCheck ?? this.lastCheck,
    );
  }
}
