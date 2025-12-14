class LocationEntity {
  final double latitude;
  final double longitude;
  final double? accuracy;
  final DateTime timestamp;

  const LocationEntity({
    required this.latitude,
    required this.longitude,
    this.accuracy,
    required this.timestamp,
  });

  factory LocationEntity.fromPosition({
    required double latitude,
    required double longitude,
    double? accuracy,
  }) {
    return LocationEntity(
      latitude: latitude,
      longitude: longitude,
      accuracy: accuracy,
      timestamp: DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'LocationEntity(lat: $latitude, lng: $longitude, accuracy: $accuracy)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is LocationEntity &&
        other.latitude == latitude &&
        other.longitude == longitude;
  }

  @override
  int get hashCode => latitude.hashCode ^ longitude.hashCode;
}
