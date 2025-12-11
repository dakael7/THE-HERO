import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';

class AnimatedRoleButton extends StatefulWidget {
  final Widget contentWidget;
  final String label;
  final String description;
  final Color color;
  final Color textColor;
  final Color descriptionColor;
  final VoidCallback onTap;

  const AnimatedRoleButton({
    Key? key,
    required this.contentWidget,
    required this.label,
    required this.description,
    required this.color,
    required this.textColor,
    required this.descriptionColor,
    required this.onTap,
  }) : super(key: key);

  @override
  State<AnimatedRoleButton> createState() => _AnimatedRoleButtonState();
}

class _AnimatedRoleButtonState extends State<AnimatedRoleButton> {
  bool _isPressed = false;
  static const Duration _animationDuration = Duration(milliseconds: 150);
  static const double _scaleFactor = 1.02;

  Color _getAnimatedColor(bool isOrangeButton) {
    if (!_isPressed) {
      return widget.color;
    }

    if (isOrangeButton) {
      return const Color(0xFFFFB74D);
    } else {
      return const Color(0xFFFFE0B2);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOrange = widget.color == primaryOrange;

    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        Future.delayed(_animationDuration, () {
          if (mounted) {
            widget.onTap();
          }
        });
        setState(() => _isPressed = false);
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedContainer(
        duration: _animationDuration,
        curve: Curves.easeOut,
        transform: Matrix4.identity()..scale(_isPressed ? _scaleFactor : 1.0),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 25, horizontal: 20),
        decoration: BoxDecoration(
          color: _getAnimatedColor(isOrange),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isOrange ? Colors.white : primaryOrange,
            width: 2.0,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black26.withOpacity(_isPressed ? 0.15 : 0.26),
              blurRadius: _isPressed ? 5 : 10,
              offset: Offset(0, _isPressed ? 2 : 5),
            ),
          ],
        ),
        child: Column(
          children: [
            widget.contentWidget,
            const SizedBox(height: 10),
            Text(
              widget.label,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w500,
                color: widget.textColor,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              widget.description,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w400,
                color: widget.descriptionColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
