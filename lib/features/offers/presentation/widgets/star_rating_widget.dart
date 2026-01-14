import 'package:flutter/material.dart';

class StarRatingWidget extends StatelessWidget {
  final double rating; // 0.0 to 5.0
  final double size;
  final bool readonly;
  final ValueChanged<int>? onRatingChanged;
  final Color activeColor;
  final Color inactiveColor;

  const StarRatingWidget({
    super.key,
    required this.rating,
    this.size = 20.0,
    this.readonly = true,
    this.onRatingChanged,
    this.activeColor = const Color(0xFFFFB800),
    this.inactiveColor = const Color(0xFFE0E0E0),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isFilled = rating >= starValue;
        final isHalfFilled = !isFilled && rating > index && rating < starValue;

        return GestureDetector(
          onTap: readonly
              ? null
              : () {
                  if (onRatingChanged != null) {
                    onRatingChanged!(starValue);
                  }
                },
          child: Icon(
            isHalfFilled
                ? Icons.star_half
                : isFilled
                ? Icons.star
                : Icons.star_border,
            size: size,
            color: (isFilled || isHalfFilled) ? activeColor : inactiveColor,
          ),
        );
      }),
    );
  }
}

// Interactive version for user input
class StarRatingInput extends StatefulWidget {
  final int initialRating;
  final ValueChanged<int> onRatingChanged;
  final double size;

  const StarRatingInput({
    super.key,
    this.initialRating = 0,
    required this.onRatingChanged,
    this.size = 32.0,
  });

  @override
  State<StarRatingInput> createState() => _StarRatingInputState();
}

class _StarRatingInputState extends State<StarRatingInput> {
  late int _currentRating;

  @override
  void initState() {
    super.initState();
    _currentRating = widget.initialRating;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final isFilled = _currentRating >= starValue;

        return GestureDetector(
          onTap: () {
            setState(() {
              _currentRating = starValue;
            });
            widget.onRatingChanged(starValue);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4.0),
            child: Icon(
              isFilled ? Icons.star : Icons.star_border,
              size: widget.size,
              color: isFilled
                  ? const Color(0xFFFFB800)
                  : const Color(0xFFE0E0E0),
            ),
          ),
        );
      }),
    );
  }
}
