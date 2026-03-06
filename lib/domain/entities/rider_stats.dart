class RiderStats {
  final double totalEarnings;
  final double totalTips;
  final int completedTrips;
  final int canceledTrips;
  final double pendingBalance;

  const RiderStats({
    required this.totalEarnings,
    required this.totalTips,
    required this.completedTrips,
    required this.canceledTrips,
    required this.pendingBalance,
  });

  int get totalTrips => completedTrips + canceledTrips;
}
