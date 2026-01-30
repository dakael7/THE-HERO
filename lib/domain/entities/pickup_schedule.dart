/// Días de la semana disponibles para retiro
enum WeekDay {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday;

  String get displayName {
    switch (this) {
      case WeekDay.monday:
        return 'Lunes';
      case WeekDay.tuesday:
        return 'Martes';
      case WeekDay.wednesday:
        return 'Miércoles';
      case WeekDay.thursday:
        return 'Jueves';
      case WeekDay.friday:
        return 'Viernes';
      case WeekDay.saturday:
        return 'Sábado';
      case WeekDay.sunday:
        return 'Domingo';
    }
  }

  String get shortName {
    switch (this) {
      case WeekDay.monday:
        return 'Lun';
      case WeekDay.tuesday:
        return 'Mar';
      case WeekDay.wednesday:
        return 'Mié';
      case WeekDay.thursday:
        return 'Jue';
      case WeekDay.friday:
        return 'Vie';
      case WeekDay.saturday:
        return 'Sáb';
      case WeekDay.sunday:
        return 'Dom';
    }
  }

  /// Convierte DateTime.weekday (1-7) a WeekDay
  static WeekDay fromDateTime(DateTime dateTime) {
    switch (dateTime.weekday) {
      case DateTime.monday:
        return WeekDay.monday;
      case DateTime.tuesday:
        return WeekDay.tuesday;
      case DateTime.wednesday:
        return WeekDay.wednesday;
      case DateTime.thursday:
        return WeekDay.thursday;
      case DateTime.friday:
        return WeekDay.friday;
      case DateTime.saturday:
        return WeekDay.saturday;
      case DateTime.sunday:
        return WeekDay.sunday;
      default:
        throw ArgumentError('Invalid weekday: ${dateTime.weekday}');
    }
  }

  static WeekDay fromString(String value) {
    return WeekDay.values.firstWhere(
      (day) => day.name.toLowerCase() == value.toLowerCase(),
      orElse: () => throw ArgumentError('Invalid weekday: $value'),
    );
  }
}

/// Rango de tiempo para un día específico
class TimeRange {
  final String start; // Formato: "HH:mm" (24 horas)
  final String end; // Formato: "HH:mm" (24 horas)

  const TimeRange({required this.start, required this.end});

  /// Verifica si una hora específica está dentro del rango
  bool isTimeInRange(String time) {
    final timeInt = _timeToInt(time);
    final startInt = _timeToInt(start);
    final endInt = _timeToInt(end);

    return timeInt >= startInt && timeInt <= endInt;
  }

  /// Convierte "HH:mm" a minutos desde medianoche
  int _timeToInt(String time) {
    final parts = time.split(':');
    if (parts.length != 2) {
      throw ArgumentError('Invalid time format: $time. Expected HH:mm');
    }
    final hours = int.parse(parts[0]);
    final minutes = int.parse(parts[1]);
    return hours * 60 + minutes;
  }

  /// Valida que el formato de tiempo sea correcto
  static bool isValidTimeFormat(String time) {
    final regex = RegExp(r'^([0-1]?[0-9]|2[0-3]):[0-5][0-9]$');
    return regex.hasMatch(time);
  }

  Map<String, dynamic> toJson() {
    return {'start': start, 'end': end};
  }

  factory TimeRange.fromJson(Map<String, dynamic> json) {
    return TimeRange(
      start: json['start'] as String,
      end: json['end'] as String,
    );
  }

  TimeRange copyWith({String? start, String? end}) {
    return TimeRange(start: start ?? this.start, end: end ?? this.end);
  }
}

/// Horarios de retiro disponibles para una orden
class PickupSchedule {
  final List<WeekDay> availableDays;
  final Map<WeekDay, TimeRange> timeRanges;

  const PickupSchedule({required this.availableDays, required this.timeRanges});

  /// Verifica si el retiro está disponible en un momento específico
  bool isAvailableAt(DateTime dateTime) {
    final weekDay = WeekDay.fromDateTime(dateTime);

    // Verificar si el día está disponible
    if (!availableDays.contains(weekDay)) {
      return false;
    }

    // Verificar si hay rango de tiempo definido para este día
    final timeRange = timeRanges[weekDay];
    if (timeRange == null) {
      return false;
    }

    // Verificar si la hora actual está en el rango
    final currentTime =
        '${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
    return timeRange.isTimeInRange(currentTime);
  }

  /// Verifica si está disponible ahora
  bool isAvailableNow() {
    return isAvailableAt(DateTime.now());
  }

  /// Obtiene el próximo horario disponible
  DateTime? getNextAvailableTime() {
    final now = DateTime.now();

    // Buscar en los próximos 7 días
    for (int i = 0; i < 7; i++) {
      final checkDate = now.add(Duration(days: i));
      final weekDay = WeekDay.fromDateTime(checkDate);

      if (availableDays.contains(weekDay)) {
        final timeRange = timeRanges[weekDay];
        if (timeRange != null) {
          final startParts = timeRange.start.split(':');
          final nextAvailable = DateTime(
            checkDate.year,
            checkDate.month,
            checkDate.day,
            int.parse(startParts[0]),
            int.parse(startParts[1]),
          );

          // Si es hoy, verificar que no haya pasado el horario
          if (i == 0 && nextAvailable.isBefore(now)) {
            continue;
          }

          return nextAvailable;
        }
      }
    }

    return null;
  }

  /// Obtiene una descripción legible de los horarios
  String getScheduleDescription() {
    if (availableDays.isEmpty) {
      return 'Sin horarios disponibles';
    }

    final dayNames = availableDays.map((day) => day.shortName).join(', ');

    // Si todos los días tienen el mismo horario
    final firstRange = timeRanges[availableDays.first];
    if (firstRange != null &&
        timeRanges.values.every(
          (range) =>
              range.start == firstRange.start && range.end == firstRange.end,
        )) {
      return '$dayNames: ${firstRange.start} - ${firstRange.end}';
    }

    // Si tienen horarios diferentes
    return dayNames;
  }

  Map<String, dynamic> toJson() {
    return {
      'availableDays': availableDays.map((day) => day.name).toList(),
      'timeRanges': timeRanges.map(
        (key, value) => MapEntry(key.name, value.toJson()),
      ),
    };
  }

  factory PickupSchedule.fromJson(Map<String, dynamic> json) {
    final availableDays = (json['availableDays'] as List<dynamic>)
        .map((day) => WeekDay.fromString(day as String))
        .toList();

    final timeRangesMap = json['timeRanges'] as Map<String, dynamic>;
    final timeRanges = <WeekDay, TimeRange>{};

    timeRangesMap.forEach((key, value) {
      final weekDay = WeekDay.fromString(key);
      final timeRange = TimeRange.fromJson(value as Map<String, dynamic>);
      timeRanges[weekDay] = timeRange;
    });

    return PickupSchedule(availableDays: availableDays, timeRanges: timeRanges);
  }

  /// Crea un horario de lunes a viernes, 9:00 - 18:00 (por defecto)
  factory PickupSchedule.businessHours() {
    const timeRange = TimeRange(start: '09:00', end: '18:00');
    return PickupSchedule(
      availableDays: [
        WeekDay.monday,
        WeekDay.tuesday,
        WeekDay.wednesday,
        WeekDay.thursday,
        WeekDay.friday,
      ],
      timeRanges: {
        WeekDay.monday: timeRange,
        WeekDay.tuesday: timeRange,
        WeekDay.wednesday: timeRange,
        WeekDay.thursday: timeRange,
        WeekDay.friday: timeRange,
      },
    );
  }

  /// Crea un horario disponible todos los días, todo el día
  factory PickupSchedule.allDay() {
    const timeRange = TimeRange(start: '00:00', end: '23:59');
    final allDays = WeekDay.values;
    return PickupSchedule(
      availableDays: allDays,
      timeRanges: Map.fromEntries(
        allDays.map((day) => MapEntry(day, timeRange)),
      ),
    );
  }

  PickupSchedule copyWith({
    List<WeekDay>? availableDays,
    Map<WeekDay, TimeRange>? timeRanges,
  }) {
    return PickupSchedule(
      availableDays: availableDays ?? this.availableDays,
      timeRanges: timeRanges ?? this.timeRanges,
    );
  }
}
