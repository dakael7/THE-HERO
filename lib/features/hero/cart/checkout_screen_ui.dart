part of 'checkout_screen.dart';

// -----------------------------------------------------------------------------
//  SHARED DESIGN PRIMITIVES
// -----------------------------------------------------------------------------

String _checkoutStageLabel(_CheckoutStage stage) {
  switch (stage) {
    case _CheckoutStage.delivery:
      return 'Entrega';
    case _CheckoutStage.document:
      return 'Documento';
    case _CheckoutStage.payment:
      return 'Pago';
  }
}

IconData _checkoutStageIcon(_CheckoutStage stage) {
  switch (stage) {
    case _CheckoutStage.delivery:
      return Icons.local_shipping_rounded;
    case _CheckoutStage.document:
      return Icons.description_rounded;
    case _CheckoutStage.payment:
      return Icons.payments_rounded;
  }
}

class _CheckoutStageHeader extends StatelessWidget {
  final _CheckoutStage current;
  final ValueChanged<_CheckoutStage> onStageTap;

  const _CheckoutStageHeader({required this.current, required this.onStageTap});

  @override
  Widget build(BuildContext context) {
    final stepNumber = current.index + 1;
    final stepTotal = _CheckoutStage.values.length;
    final progress = stepNumber / stepTotal;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFECECEC)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: primaryOrange,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    '$stepNumber',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _checkoutStageLabel(current),
                      style: const TextStyle(
                        color: textGray900,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Paso $stepNumber de $stepTotal',
                      style: const TextStyle(
                        color: textGray600,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFFFED7AA)),
                ),
                child: Text(
                  '${(progress * 100).round()}%',
                  style: const TextStyle(
                    color: primaryOrange,
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: SizedBox(
              height: 7,
              child: Stack(
                children: [
                  Container(color: const Color(0xFFF3F4F6)),
                  FractionallySizedBox(
                    widthFactor: progress,
                    child: Container(color: primaryOrange),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              for (final stage in _CheckoutStage.values) ...[
                Expanded(
                  child: _CheckoutStageChip(
                    stage: stage,
                    current: current,
                    onTap: stage.index <= current.index
                        ? () => onStageTap(stage)
                        : null,
                  ),
                ),
                if (stage != _CheckoutStage.values.last)
                  const SizedBox(width: 8),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _CheckoutStageChip extends StatelessWidget {
  final _CheckoutStage stage;
  final _CheckoutStage current;
  final VoidCallback? onTap;

  const _CheckoutStageChip({
    required this.stage,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final selected = stage == current;
    final done = stage.index < current.index;
    final enabled = onTap != null;
    final color = selected || done ? primaryOrange : textGray600;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: selected
                ? const Color(0xFFFFF7ED)
                : done
                ? const Color(0xFFFFFBEB)
                : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected
                  ? primaryOrange
                  : done
                  ? const Color(0xFFFED7AA)
                  : const Color(0xFFE8E8E8),
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                done ? Icons.check_circle_rounded : _checkoutStageIcon(stage),
                size: 16,
                color: enabled ? color : const Color(0xFFD1D5DB),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  _checkoutStageLabel(stage),
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: enabled ? color : const Color(0xFFD1D5DB),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CheckoutStageActions extends StatelessWidget {
  final String? backLabel;
  final String nextLabel;
  final bool canContinue;
  final VoidCallback? onBack;
  final VoidCallback onNext;

  const _CheckoutStageActions({
    this.backLabel,
    required this.nextLabel,
    required this.canContinue,
    required this.onNext,
    this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (onBack != null) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back_rounded, size: 18),
              label: Text(backLabel ?? 'Atrás'),
              style: OutlinedButton.styleFrom(
                foregroundColor: textGray700,
                side: const BorderSide(color: Color(0xFFE8E8E8)),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: ElevatedButton.icon(
            onPressed: canContinue ? onNext : null,
            icon: const Icon(Icons.arrow_forward_rounded, size: 18),
            label: Text(nextLabel),
            style: ElevatedButton.styleFrom(
              backgroundColor: primaryOrange,
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFFD1D5DB),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionLabel({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 20,
          decoration: BoxDecoration(
            color: primaryOrange,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: primaryOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 14, color: primaryOrange),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 15,
            color: textGray900,
            letterSpacing: -0.3,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;

  const _SectionCard({required this.child, this.padding});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding ?? const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFECECEC)),
      ),
      child: child,
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    return Container(height: 1, color: const Color(0xFFF2F2F2));
  }
}

/// Styled input field matching the design system
class _StyledField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final IconData icon;
  final bool readOnly;
  final int? maxLines;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final VoidCallback? onTap;
  final Widget? suffix;
  final ValueChanged<String>? onChanged;
  final List<TextInputFormatter>? inputFormatters;

  const _StyledField({
    required this.controller,
    required this.label,
    required this.icon,
    this.hint,
    this.readOnly = false,
    this.maxLines = 1,
    this.keyboardType,
    this.validator,
    this.onTap,
    this.suffix,
    this.onChanged,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      onTap: onTap,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: const Color(0xFFFAFAFA),
        prefixIcon: Container(
          margin: const EdgeInsets.all(10),
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: primaryOrange.withValues(alpha: 0.09),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(icon, size: 15, color: primaryOrange),
        ),
        suffixIcon: suffix != null
            ? Padding(padding: const EdgeInsets.only(right: 8), child: suffix)
            : null,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFE8E8E8)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: primaryOrange, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.5),
        ),
        labelStyle: const TextStyle(
          color: textGray600,
          fontWeight: FontWeight.w600,
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
      ),
    );
  }
}

/// Toggle row (replaces SwitchListTile)
class _ToggleRow extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;

  const _ToggleRow({
    required this.value,
    required this.onChanged,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 17, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: textGray900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: textGray600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Switch.adaptive(
          value: value,
          onChanged: onChanged,
          activeColor: primaryOrange,
          activeTrackColor: primaryOrange.withValues(alpha: 0.2),
        ),
      ],
    );
  }
}

/// Warning banner
class _WarningBanner extends StatelessWidget {
  final String message;
  const _WarningBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(
              color: const Color(0xFFEA580C).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: const Icon(
              Icons.info_rounded,
              size: 13,
              color: Color(0xFFEA580C),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w700,
                height: 1.35,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Summary row
class _SummaryRow extends StatelessWidget {
  final String label;
  final String value;
  final String? sub;

  const _SummaryRow({required this.label, required this.value, this.sub});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: textGray700,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
            ),
          ],
        ),
        if (sub != null) ...[
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              sub!,
              style: const TextStyle(
                fontSize: 11,
                color: textGray600,
                fontStyle: FontStyle.italic,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PREMIUM DIALOGS
// ─────────────────────────────────────────────────────────────────────────────

class _PremiumAlertDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  const _PremiumAlertDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              message,
              style: const TextStyle(
                fontSize: 13,
                color: textGray700,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onAction,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryOrange,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  actionLabel,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PremiumResultDialog extends StatelessWidget {
  final bool success;
  final String? message;
  final VoidCallback onClose;

  const _PremiumResultDialog({
    required this.success,
    this.message,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final color = success ? const Color(0xFF10B981) : const Color(0xFFDC2626);
    final icon = success ? Icons.check_circle_rounded : Icons.error_rounded;
    final title = success ? 'Solicitud enviada' : 'Pago fallido';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 400),
              curve: Curves.easeOutBack,
              builder: (context, value, child) {
                return Transform.scale(
                  scale: value,
                  child: Opacity(opacity: value.clamp(0, 1), child: child),
                );
              },
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                style: const TextStyle(
                  fontSize: 13,
                  color: textGray700,
                  height: 1.5,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: onClose,
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  success ? 'Continuar' : 'Entendido',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  ROUTE MAP (unchanged logic, refined visuals)
// ─────────────────────────────────────────────────────────────────────────────

class _OsrmLeg {
  final double distanceMeters;
  final double durationSeconds;

  const _OsrmLeg({required this.distanceMeters, required this.durationSeconds});
}

class _OsrmTrip {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final List<String> orderedPickupKeys;
  final List<_OsrmLeg> legs;

  const _OsrmTrip({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    required this.orderedPickupKeys,
    required this.legs,
  });
}

class _CheckoutItemsRouteMap extends StatelessWidget {
  final List<CartItem> cartItems;
  final firestore.GeoPoint? deliveryGeo;
  final bool isLoading;
  final Object? error;
  final _OsrmTrip? trip;
  final VoidCallback? onRetry;

  const _CheckoutItemsRouteMap({
    required this.cartItems,
    required this.deliveryGeo,
    required this.isLoading,
    required this.error,
    required this.trip,
    required this.onRetry,
  });

  bool _isValidGeo(firestore.GeoPoint? geo) {
    if (geo == null) return false;
    if (geo.latitude == 0 && geo.longitude == 0) return false;
    return geo.latitude >= -90 &&
        geo.latitude <= 90 &&
        geo.longitude >= -180 &&
        geo.longitude <= 180;
  }

  String _formatKm(double meters) {
    final km = meters / 1000.0;
    return '${km.toStringAsFixed(km < 10 ? 1 : 0)} km';
  }

  String _formatMin(double seconds) {
    final min = (seconds / 60.0).round();
    return '$min min';
  }

  @override
  Widget build(BuildContext context) {
    final delivery = deliveryGeo;
    final hasDelivery = _isValidGeo(delivery);

    final pickupGeos = cartItems
        .map((e) => e.pickupGeo)
        .where(_isValidGeo)
        .cast<firestore.GeoPoint>()
        .toList();

    final uniquePickups = <String, firestore.GeoPoint>{};
    for (final geo in pickupGeos) {
      final key =
          '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
      uniquePickups[key] = geo;
    }

    final hasPickups = uniquePickups.isNotEmpty;
    final canShowMap = hasDelivery && hasPickups;

    if (!canShowMap) {
      return _RoutePreviewPlaceholder(
        hasPickups: hasPickups,
        pickupCount: uniquePickups.length,
      );
    }

    final deliveryLatLng = gmap.LatLng(delivery!.latitude, delivery.longitude);

    final pickupEntries = uniquePickups.entries.toList();
    pickupEntries.sort((a, b) => a.key.compareTo(b.key));

    final orderedKeys = trip?.orderedPickupKeys ?? <String>[];

    String keyForGeo(firestore.GeoPoint geo) {
      return '${geo.latitude.toStringAsFixed(6)},${geo.longitude.toStringAsFixed(6)}';
    }

    final itemsByPickupKey = <String, List<CartItem>>{};
    for (final item in cartItems) {
      final geo = item.pickupGeo;
      if (!_isValidGeo(geo)) continue;
      final key = keyForGeo(geo!);
      (itemsByPickupKey[key] ??= <CartItem>[]).add(item);
    }

    final colors = <Color>[
      const Color(0xFF2563EB),
      const Color(0xFF16A34A),
      const Color(0xFFDC2626),
      const Color(0xFF7C3AED),
    ];

    final polylines = <gmap.Polyline>{
      if (trip != null)
        gmap.Polyline(
          polylineId: const gmap.PolylineId('checkout_route'),
          points: trip!.points
              .map((p) => gmap.LatLng(p.latitude, p.longitude))
              .toList(growable: false),
          width: 5,
          color: const Color(0xFF0F172A).withValues(alpha: 0.85),
          geodesic: true,
          zIndex: 5,
        ),
    };

    final markers = <gmap.Marker>{
      for (var i = 0; i < orderedKeys.length; i++)
        if (uniquePickups[orderedKeys[i]] != null)
          gmap.Marker(
            markerId: gmap.MarkerId('pickup_${i + 1}'),
            position: gmap.LatLng(
              uniquePickups[orderedKeys[i]]!.latitude,
              uniquePickups[orderedKeys[i]]!.longitude,
            ),
            icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
              <double>[
                gmap.BitmapDescriptor.hueAzure,
                gmap.BitmapDescriptor.hueGreen,
                gmap.BitmapDescriptor.hueRed,
                gmap.BitmapDescriptor.hueViolet,
              ][i % 4],
            ),
            infoWindow: gmap.InfoWindow(
              title: 'Retiro ${i + 1}',
              snippet:
                  '${itemsByPickupKey[orderedKeys[i]]?.length ?? 0} item(s)',
            ),
          ),
      gmap.Marker(
        markerId: const gmap.MarkerId('delivery'),
        position: deliveryLatLng,
        icon: gmap.BitmapDescriptor.defaultMarkerWithHue(
          gmap.BitmapDescriptor.hueOrange,
        ),
        infoWindow: const gmap.InfoWindow(title: 'Entrega'),
      ),
    };

    gmap.LatLngBounds boundsFromPoints(List<gmap.LatLng> points) {
      var minLat = points.first.latitude;
      var maxLat = points.first.latitude;
      var minLng = points.first.longitude;
      var maxLng = points.first.longitude;
      for (final p in points.skip(1)) {
        if (p.latitude < minLat) minLat = p.latitude;
        if (p.latitude > maxLat) maxLat = p.latitude;
        if (p.longitude < minLng) minLng = p.longitude;
        if (p.longitude > maxLng) maxLng = p.longitude;
      }
      return gmap.LatLngBounds(
        southwest: gmap.LatLng(minLat, minLng),
        northeast: gmap.LatLng(maxLat, maxLng),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFECECEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.map_rounded,
                    size: 16,
                    color: primaryOrange,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Ruta de entrega',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14,
                          color: textGray900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${pickupEntries.length} retiro${pickupEntries.length == 1 ? '' : 's'} hacia tu destino',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: textGray600,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFFED7AA)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isLoading) ...[
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else ...[
                        const Icon(
                          Icons.route_rounded,
                          size: 12,
                          color: primaryOrange,
                        ),
                        const SizedBox(width: 5),
                      ],
                      Text(
                        isLoading ? 'Calculando' : 'Activa',
                        style: const TextStyle(
                          color: primaryOrange,
                          fontSize: 11,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 224,
                child: gmap.GoogleMap(
                  initialCameraPosition: gmap.CameraPosition(
                    target: deliveryLatLng,
                    zoom: 12,
                  ),
                  markers: markers,
                  polylines: polylines,
                  gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
                    Factory<OneSequenceGestureRecognizer>(
                      () => EagerGestureRecognizer(),
                    ),
                  },
                  zoomGesturesEnabled: true,
                  scrollGesturesEnabled: true,
                  rotateGesturesEnabled: true,
                  tiltGesturesEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                  liteModeEnabled: Env.mapsLiteMode,
                  onMapCreated: (controller) {
                    final boundsPoints = <gmap.LatLng>[
                      deliveryLatLng,
                      for (final geo in uniquePickups.values)
                        gmap.LatLng(geo.latitude, geo.longitude),
                      if (trip != null)
                        ...trip!.points.map(
                          (p) => gmap.LatLng(p.latitude, p.longitude),
                        ),
                    ];
                    if (boundsPoints.length < 2) return;
                    final b = boundsFromPoints(boundsPoints);
                    unawaited(() async {
                      final moved = await animateCameraWhenMapReady(
                        controller: controller,
                        cameraUpdateBuilder: () =>
                            gmap.CameraUpdate.newLatLngBounds(b, 42),
                      );
                      if (!moved) {
                        debugPrint('[Checkout] Could not fit map bounds');
                      }
                    }());
                  },
                ),
              ),
            ),
          ),
          if (error == null && trip == null)
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: _RoutePendingSummary(),
            ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: const Color(0xFFDC2626).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Icon(
                          Icons.error_rounded,
                          size: 13,
                          color: Color(0xFFDC2626),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          () {
                            final err = error;
                            if (err is _RouteCalculationException) {
                              return err.userMessage;
                            }
                            return 'No se pudo calcular la ruta. Reintenta.';
                          }(),
                          style: const TextStyle(
                            color: Color(0xFF991B1B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            height: 1.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  GestureDetector(
                    onTap: isLoading ? null : onRetry,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 9,
                      ),
                      decoration: BoxDecoration(
                        color: backgroundGray50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFE0E0E0)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: textGray700,
                          ),
                          SizedBox(width: 6),
                          Text(
                            'Reintentar',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: textGray700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            )
          else if (trip != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Total route summary
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundGray50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE8E8E8)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: primaryOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                            Icons.route_rounded,
                            size: 13,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ruta total: ${_formatKm(trip!.distanceMeters)}',
                            style: const TextStyle(
                              color: textGray900,
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: const Color(0xFFE0E0E0)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 11,
                                color: textGray600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _formatMin(trip!.durationSeconds),
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                  color: textGray900,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  for (
                    var stopIndex = 0;
                    stopIndex < orderedKeys.length;
                    stopIndex++
                  ) ...[
                    _RouteStopCard(
                      index: stopIndex + 1,
                      color: colors[stopIndex % colors.length],
                      title: 'Punto ${stopIndex + 1}',
                      subtitle: () {
                        final items =
                            itemsByPickupKey[orderedKeys[stopIndex]] ??
                            const <CartItem>[];
                        final qty = items.fold<int>(
                          0,
                          (sum, e) => sum + e.quantity,
                        );
                        final names = items
                            .map((e) => e.name)
                            .where((e) => e.trim().isNotEmpty)
                            .toList();
                        final firstTwo = names.take(2).join(' · ');
                        if (firstTwo.isEmpty) {
                          return '$qty artículo${qty == 1 ? '' : 's'}';
                        }
                        return '$qty artículo${qty == 1 ? '' : 's'} · $firstTwo${names.length > 2 ? '…' : ''}';
                      }(),
                      trailing: stopIndex < trip!.legs.length
                          ? _LegChips(
                              leg: trip!.legs[stopIndex],
                              formatKm: _formatKm,
                              formatMin: _formatMin,
                            )
                          : null,
                    ),
                    if (stopIndex < orderedKeys.length - 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 22),
                        child: Container(
                          width: 2,
                          height: 8,
                          color: const Color(0xFFE8E8E8),
                        ),
                      ),
                  ],
                  const SizedBox(height: 6),
                  _RouteStopCard(
                    index: orderedKeys.length + 1,
                    color: const Color(0xFF111827),
                    title: 'Entrega',
                    subtitle: 'Destino final',
                    trailing: orderedKeys.length < trip!.legs.length
                        ? _LegChips(
                            leg: trip!.legs[orderedKeys.length],
                            formatKm: _formatKm,
                            formatMin: _formatMin,
                          )
                        : null,
                    icon: Icons.flag_circle_rounded,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoutePreviewPlaceholder extends StatelessWidget {
  final bool hasPickups;
  final int pickupCount;

  const _RoutePreviewPlaceholder({
    required this.hasPickups,
    required this.pickupCount,
  });

  @override
  Widget build(BuildContext context) {
    final message = hasPickups
        ? 'Elige tu dirección con Google Maps para ver la ruta del rider.'
        : 'Falta una ubicación de retiro válida para calcular la ruta.';

    Widget point({
      required IconData icon,
      required String label,
      required Color color,
    }) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: color.withValues(alpha: 0.25)),
            ),
            child: Icon(icon, color: color, size: 21),
          ),
          const SizedBox(height: 7),
          Text(
            label,
            style: const TextStyle(
              color: textGray700,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFECECEC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.route_rounded,
                    size: 16,
                    color: primaryOrange,
                  ),
                ),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text(
                    'Ruta de entrega',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 14,
                      color: textGray900,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: backgroundGray50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFE8E8E8)),
                  ),
                  child: const Text(
                    'Pendiente',
                    style: TextStyle(
                      color: textGray600,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: backgroundGray50,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFE8E8E8)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      point(
                        icon: Icons.storefront_rounded,
                        label: hasPickups
                            ? '$pickupCount retiro${pickupCount == 1 ? '' : 's'}'
                            : 'Retiro',
                        color: const Color(0xFF2563EB),
                      ),
                      Expanded(
                        child: Container(
                          height: 3,
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                          decoration: BoxDecoration(
                            color: primaryOrange.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                      ),
                      point(
                        icon: Icons.flag_rounded,
                        label: 'Entrega',
                        color: primaryOrange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: textGray700,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RoutePendingSummary extends StatelessWidget {
  const _RoutePendingSummary();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8E8E8)),
      ),
      child: const Row(
        children: [
          Icon(Icons.sync_rounded, size: 15, color: textGray600),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Calculando distancia y tiempo de ruta...',
              style: TextStyle(
                color: textGray700,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LegChips extends StatelessWidget {
  final _OsrmLeg leg;
  final String Function(double meters) formatKm;
  final String Function(double seconds) formatMin;

  const _LegChips({
    required this.leg,
    required this.formatKm,
    required this.formatMin,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      alignment: WrapAlignment.end,
      children: [
        _PillChip(
          icon: Icons.straighten_rounded,
          label: formatKm(leg.distanceMeters),
        ),
        _PillChip(
          icon: Icons.schedule_rounded,
          label: formatMin(leg.durationSeconds),
        ),
      ],
    );
  }
}

class _RouteStopCard extends StatelessWidget {
  final int index;
  final Color color;
  final String title;
  final String subtitle;
  final Widget? trailing;
  final IconData icon;

  const _RouteStopCard({
    required this.index,
    required this.color,
    required this.title,
    required this.subtitle,
    this.trailing,
    this.icon = Icons.location_on_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 420;

        final indexBadge = Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Text(
              '$index',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
        );

        final titleRow = Row(
          children: [
            Icon(icon, size: 15, color: textGray900),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        );

        final subtitleText = Text(
          subtitle,
          maxLines: isNarrow ? 2 : 3,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: textGray600,
            height: 1.3,
          ),
        );

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleRow,
            const SizedBox(height: 3),
            subtitleText,
            if (isNarrow && trailing != null) ...[
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerRight, child: trailing!),
            ],
          ],
        );

        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFECECEC)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              indexBadge,
              const SizedBox(width: 10),
              Expanded(child: content),
              if (!isNarrow && trailing != null) ...[
                const SizedBox(width: 8),
                Flexible(fit: FlexFit.loose, child: trailing!),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _PillChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _PillChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: backgroundGray50,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE0E0E0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: textGray600),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: textGray900,
            ),
          ),
        ],
      ),
    );
  }
}
