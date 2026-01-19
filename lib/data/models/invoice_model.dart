import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/invoice.dart';

class InvoiceModel {
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

  const InvoiceModel({
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
    required this.currency,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  factory InvoiceModel.fromEntity(Invoice invoice) {
    return InvoiceModel(
      id: invoice.id,
      orderId: invoice.orderId,
      customerId: invoice.customerId,
      riderId: invoice.riderId,
      issuer: invoice.issuer,
      receiver: invoice.receiver,
      issueDate: invoice.issueDate,
      dueDate: invoice.dueDate,
      number: invoice.number,
      folio: invoice.folio,
      lines: invoice.lines,
      subTotal: invoice.subTotal,
      taxAmount: invoice.taxAmount,
      total: invoice.total,
      paymentTerms: invoice.paymentTerms,
      currency: invoice.currency,
      status: invoice.status,
      createdAt: invoice.createdAt,
      updatedAt: invoice.updatedAt,
    );
  }

  Invoice toEntity() {
    return Invoice(
      id: id,
      orderId: orderId,
      customerId: customerId,
      riderId: riderId,
      issuer: issuer,
      receiver: receiver,
      issueDate: issueDate,
      dueDate: dueDate,
      number: number,
      folio: folio,
      lines: lines,
      subTotal: subTotal,
      taxAmount: taxAmount,
      total: total,
      paymentTerms: paymentTerms,
      currency: currency,
      status: status,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'orderId': orderId,
      'customerId': customerId,
      'riderId': riderId,
      'issuer': _partyToJson(issuer),
      'receiver': _partyToJson(receiver),
      'issueDate': Timestamp.fromDate(issueDate),
      'dueDate': dueDate != null ? Timestamp.fromDate(dueDate!) : null,
      'number': number,
      'folio': folio,
      'lines': lines.map(_lineToJson).toList(),
      'subTotal': subTotal,
      'taxAmount': taxAmount,
      'total': total,
      'paymentTerms': _termsToJson(paymentTerms),
      'currency': currency,
      'status': status.name,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
    };
  }

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    return InvoiceModel(
      id: json['id'] as String,
      orderId: json['orderId'] as String,
      customerId: json['customerId'] as String,
      riderId: json['riderId'] as String?,
      issuer: _partyFromJson(json['issuer'] as Map<String, dynamic>),
      receiver: _partyFromJson(json['receiver'] as Map<String, dynamic>),
      issueDate: (json['issueDate'] as Timestamp).toDate(),
      dueDate: json['dueDate'] != null ? (json['dueDate'] as Timestamp).toDate() : null,
      number: json['number'] as String,
      folio: json['folio'] as String?,
      lines: (json['lines'] as List)
          .map((e) => _lineFromJson(e as Map<String, dynamic>))
          .toList(),
      subTotal: (json['subTotal'] as num).toDouble(),
      taxAmount: (json['taxAmount'] as num).toDouble(),
      total: (json['total'] as num).toDouble(),
      paymentTerms: _termsFromJson(json['paymentTerms'] as Map<String, dynamic>),
      currency: (json['currency'] as String?) ?? 'CLP',
      status: InvoiceStatus.values.firstWhere(
        (s) => s.name == json['status'],
        orElse: () => InvoiceStatus.issued,
      ),
      createdAt: (json['createdAt'] as Timestamp).toDate(),
      updatedAt: (json['updatedAt'] as Timestamp).toDate(),
    );
  }

  static Map<String, dynamic> _partyToJson(InvoiceParty party) => {
        'name': party.name,
        'rut': party.rut,
        'address': party.address,
        'businessActivity': party.businessActivity,
      };

  static InvoiceParty _partyFromJson(Map<String, dynamic> json) => InvoiceParty(
        name: json['name'] as String,
        rut: json['rut'] as String,
        address: json['address'] as String,
        businessActivity: json['businessActivity'] as String,
      );

  static Map<String, dynamic> _lineToJson(InvoiceLine line) => {
        'description': line.description,
        'quantity': line.quantity,
        'unitPrice': line.unitPrice,
        'lineTotal': line.lineTotal,
        'taxRate': line.taxRate,
      };

  static InvoiceLine _lineFromJson(Map<String, dynamic> json) => InvoiceLine(
        description: json['description'] as String,
        quantity: json['quantity'] as int,
        unitPrice: (json['unitPrice'] as num).toDouble(),
        lineTotal: (json['lineTotal'] as num).toDouble(),
        taxRate: (json['taxRate'] as num?)?.toDouble(),
      );

  static Map<String, dynamic> _termsToJson(InvoicePaymentTerms terms) => {
        'conditions': terms.conditions,
        'methods': terms.methods,
        'dueDate': terms.dueDate != null ? Timestamp.fromDate(terms.dueDate!) : null,
      };

  static InvoicePaymentTerms _termsFromJson(Map<String, dynamic> json) => InvoicePaymentTerms(
        conditions: json['conditions'] as String,
        methods: List<String>.from(json['methods'] as List),
        dueDate: json['dueDate'] != null ? (json['dueDate'] as Timestamp).toDate() : null,
      );
}
