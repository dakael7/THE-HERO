import '../../domain/entities/pickup_schedule.dart';

class PickupScheduleModel {
  final List<String> availableDays;
  final Map<String, Map<String, String>> timeRanges;

  const PickupScheduleModel({
    required this.availableDays,
    required this.timeRanges,
  });

  factory PickupScheduleModel.fromJson(Map<String, dynamic> json) {
    final availableDays =
        (json['availableDays'] as List<dynamic>?)
            ?.map((day) => day as String)
            .toList() ??
        [];

    final timeRangesJson = json['timeRanges'] as Map<String, dynamic>? ?? {};
    final timeRanges = <String, Map<String, String>>{};

    timeRangesJson.forEach((key, value) {
      if (value is Map<String, dynamic>) {
        timeRanges[key] = {
          'start': value['start'] as String? ?? '09:00',
          'end': value['end'] as String? ?? '18:00',
        };
      }
    });

    return PickupScheduleModel(
      availableDays: availableDays,
      timeRanges: timeRanges,
    );
  }

  Map<String, dynamic> toJson() {
    return {'availableDays': availableDays, 'timeRanges': timeRanges};
  }

  PickupSchedule toEntity() {
    final weekDays = availableDays
        .map((day) {
          try {
            return WeekDay.fromString(day);
          } catch (e) {
            return null;
          }
        })
        .whereType<WeekDay>()
        .toList();

    final entityTimeRanges = <WeekDay, TimeRange>{};
    timeRanges.forEach((key, value) {
      try {
        final weekDay = WeekDay.fromString(key);
        final timeRange = TimeRange(
          start: value['start'] ?? '09:00',
          end: value['end'] ?? '18:00',
        );
        entityTimeRanges[weekDay] = timeRange;
      } catch (e) {
        // Skip invalid entries
      }
    });

    return PickupSchedule(
      availableDays: weekDays,
      timeRanges: entityTimeRanges,
    );
  }

  factory PickupScheduleModel.fromEntity(PickupSchedule entity) {
    final availableDays = entity.availableDays.map((day) => day.name).toList();

    final timeRanges = <String, Map<String, String>>{};
    entity.timeRanges.forEach((key, value) {
      timeRanges[key.name] = {'start': value.start, 'end': value.end};
    });

    return PickupScheduleModel(
      availableDays: availableDays,
      timeRanges: timeRanges,
    );
  }
}
