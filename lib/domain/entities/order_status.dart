enum OrderStatus {
  created,
  pendingPayment,
  paid,
  queued,
  assigned,
  pickedUp,
  inTransit,
  delivered,
  canceled,
  failed;

  String get displayName {
    switch (this) {
      case OrderStatus.created:
        return 'Creado';
      case OrderStatus.pendingPayment:
        return 'Pendiente de pago';
      case OrderStatus.paid:
        return 'Pagado';
      case OrderStatus.queued:
        return 'En cola';
      case OrderStatus.assigned:
        return 'Asignado';
      case OrderStatus.pickedUp:
        return 'Recogido';
      case OrderStatus.inTransit:
        return 'En tránsito';
      case OrderStatus.delivered:
        return 'Entregado';
      case OrderStatus.canceled:
        return 'Cancelado';
      case OrderStatus.failed:
        return 'Fallido';
    }
  }

  bool get isActive {
    return this == OrderStatus.assigned ||
           this == OrderStatus.pickedUp ||
           this == OrderStatus.inTransit;
  }

  bool get isCompleted {
    return this == OrderStatus.delivered ||
           this == OrderStatus.canceled ||
           this == OrderStatus.failed;
  }

  bool get canBeCanceled {
    return this == OrderStatus.created ||
           this == OrderStatus.pendingPayment ||
           this == OrderStatus.paid ||
           this == OrderStatus.queued;
  }
}
