import 'order_item.dart';

class Invoice {
  final String id;
  final String orderId;
  final String customerId;
  final String? riderId;
  final InvoiceParty issuer;
  final InvoiceParty receiver;
  final DateTime issueDate;
  final DateTime? dueDate;
  final String number;
  final String? folio; 
  final List<InvoiceLine> lines;
  final double subTotal;
  final double taxAmount; 
  final double total;
  final InvoicePaymentTerms paymentTerms;
  final String currency; 
  final InvoiceStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Invoice({
    required this.id,
    required this.orderId,
    required this.customerId,
    this.riderId,
    required this.issuer,
    required this.receiver,
    required this.issueDate,
    this.dueDate,
    required this.number,
    this.folio,
    required this.lines,
    required this.subTotal,
    required this.taxAmount,
    required this.total,
    required this.paymentTerms,
    this.currency = 'CLP',
    this.status = InvoiceStatus.issued,
    required this.createdAt,
    required this.updatedAt,
  });
}

enum InvoiceStatus { issued, paid, voided }

class InvoiceParty {
  final String name;
  final String rut;
  final String address;
  final String businessActivity; 

  const InvoiceParty({
    required this.name,
    required this.rut,
    required this.address,
    required this.businessActivity,
  });
}

class InvoiceLine {
  final String description;
  final int quantity;
  final double unitPrice;
  final double lineTotal;
  final double? taxRate; // 

  const InvoiceLine({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
    this.taxRate,
  });

  factory InvoiceLine.fromOrderItem(OrderItem item, {double? taxRate}) {
    final total = item.unitPriceSnapshot * item.qty;
    return InvoiceLine(
      description: item.titleSnapshot,
      quantity: item.qty,
      unitPrice: item.unitPriceSnapshot,
      lineTotal: total,
      taxRate: taxRate,
    );
  }
}

class InvoicePaymentTerms {
  final String conditions; // ej: "30 días"
  final List<String> methods; // ej: ["Transferencia", "Crédito"]
  final DateTime? dueDate;

  const InvoicePaymentTerms({
    required this.conditions,
    required this.methods,
    this.dueDate,
  });
}
