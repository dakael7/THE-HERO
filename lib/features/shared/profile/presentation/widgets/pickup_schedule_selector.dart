import 'package:flutter/material.dart';
import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/pickup_schedule.dart';

class PickupScheduleSelector extends StatefulWidget {
  final PickupSchedule? initialSchedule;
  final Function(PickupSchedule?) onChanged;

  const PickupScheduleSelector({
    super.key,
    this.initialSchedule,
    required this.onChanged,
  });

  @override
  State<PickupScheduleSelector> createState() => _PickupScheduleSelectorState();
}

class _PickupScheduleSelectorState extends State<PickupScheduleSelector> {
  late Set<WeekDay> _selectedDays;
  late TimeOfDay _startTime;
  late TimeOfDay _endTime;

  @override
  void initState() {
    super.initState();

    // Initialize from initial schedule or use defaults
    if (widget.initialSchedule != null) {
      _selectedDays = widget.initialSchedule!.availableDays.toSet();
      final firstDay = widget.initialSchedule!.availableDays.first;
      final timeRange = widget.initialSchedule!.timeRanges[firstDay];
      if (timeRange != null) {
        final startParts = timeRange.start.split(':');
        final endParts = timeRange.end.split(':');
        _startTime = TimeOfDay(
          hour: int.parse(startParts[0]),
          minute: int.parse(startParts[1]),
        );
        _endTime = TimeOfDay(
          hour: int.parse(endParts[0]),
          minute: int.parse(endParts[1]),
        );
      } else {
        _startTime = const TimeOfDay(hour: 9, minute: 0);
        _endTime = const TimeOfDay(hour: 18, minute: 0);
      }
    } else {
      _selectedDays = {
        WeekDay.monday,
        WeekDay.tuesday,
        WeekDay.wednesday,
        WeekDay.thursday,
        WeekDay.friday,
      };
      _startTime = const TimeOfDay(hour: 9, minute: 0);
      _endTime = const TimeOfDay(hour: 18, minute: 0);
    }

  }

  @override
  void dispose() {
    super.dispose();
  }

  void _notifyChanges() {
    PickupSchedule? schedule;

    if (_selectedDays.isNotEmpty) {
      final timeRange = TimeRange(
        start:
            '${_startTime.hour.toString().padLeft(2, '0')}:${_startTime.minute.toString().padLeft(2, '0')}',
        end:
            '${_endTime.hour.toString().padLeft(2, '0')}:${_endTime.minute.toString().padLeft(2, '0')}',
      );

      final timeRanges = <WeekDay, TimeRange>{};
      for (final day in _selectedDays) {
        timeRanges[day] = timeRange;
      }

      schedule = PickupSchedule(
        availableDays: _selectedDays.toList(),
        timeRanges: timeRanges,
      );
    }

    widget.onChanged(schedule);
  }

  Future<void> _selectTime(bool isStart) async {
    final initialTime = isStart ? _startTime : _endTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: initialTime,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: primaryOrange,
              onPrimary: backgroundWhite,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isStart) {
          _startTime = picked;
        } else {
          _endTime = picked;
        }
      });
      _notifyChanges();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Horarios de Retiro',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: textGray900,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Selecciona los días y horarios en que el rider puede retirar el producto',
          style: TextStyle(fontSize: 13, color: textGray600),
        ),
        const SizedBox(height: 16),

        // Day selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Días disponibles',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: WeekDay.values.map((day) {
                  final isSelected = _selectedDays.contains(day);
                  return FilterChip(
                    label: Text(day.shortName),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selectedDays.add(day);
                        } else {
                          _selectedDays.remove(day);
                        }
                      });
                      _notifyChanges();
                    },
                    selectedColor: primaryOrange.withValues(alpha: 0.2),
                    checkmarkColor: primaryOrange,
                    labelStyle: TextStyle(
                      color: isSelected ? primaryOrange : textGray700,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Time range selector
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: backgroundWhite,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGray100),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Horario',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(true),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderGray100),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Inicio:',
                              style: TextStyle(
                                fontSize: 13,
                                color: textGray600,
                              ),
                            ),
                            Text(
                              _startTime.format(context),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InkWell(
                      onTap: () => _selectTime(false),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: backgroundGray50,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: borderGray100),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Fin:',
                              style: TextStyle(
                                fontSize: 13,
                                color: textGray600,
                              ),
                            ),
                            Text(
                              _endTime.format(context),
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: textGray900,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Info card
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9E6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: primaryYellow),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.info_outline, color: primaryOrange, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedDays.isEmpty
                      ? 'Selecciona al menos un día para que los riders puedan ver tu producto'
                      : 'Los riders solo verán tu producto durante los horarios seleccionados',
                  style: const TextStyle(fontSize: 12, color: textGray700),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
