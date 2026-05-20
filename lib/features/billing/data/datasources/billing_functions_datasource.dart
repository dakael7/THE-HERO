import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

class BillingFunctionsDataSource {
  final FirebaseFunctions _functions;

  BillingFunctionsDataSource({FirebaseFunctions? functions})
    : _functions =
          functions ?? FirebaseFunctions.instanceFor(region: 'us-central1');

  Future<void> _ensureFreshAuthToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw Exception('Debes iniciar sesion para continuar');
    }
    await user.getIdToken(true);
  }

  Future<String> getInvoiceDownloadLink(String invoiceId) async {
    if (invoiceId.trim().isEmpty) {
      throw Exception('invoiceId es requerido');
    }

    try {
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('getInvoiceDownloadLink');
      final result = await callable.call({'invoiceId': invoiceId.trim()});
      final data = result.data;
      if (data is! Map) {
        throw Exception('Respuesta invalida al descargar factura');
      }
      final url = (data['url'] as String?)?.trim();
      if (url == null || url.isEmpty) {
        throw Exception('No se recibio URL de descarga');
      }
      return url;
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is String && details.trim().isNotEmpty) {
        throw Exception(details.trim());
      }
      if (e.message != null && e.message!.trim().isNotEmpty) {
        throw Exception(e.message!.trim());
      }
      throw Exception('No se pudo abrir la factura (${e.code})');
    }
  }

  Future<void> retryInvoiceEmission(String invoiceId) async {
    if (invoiceId.trim().isEmpty) {
      throw Exception('invoiceId es requerido');
    }

    try {
      await _ensureFreshAuthToken();
      final callable = _functions.httpsCallable('retryInvoiceEmission');
      await callable.call({'invoiceId': invoiceId.trim()});
    } on FirebaseFunctionsException catch (e) {
      final details = e.details;
      if (details is String && details.trim().isNotEmpty) {
        throw Exception(details.trim());
      }
      if (e.message != null && e.message!.trim().isNotEmpty) {
        throw Exception(e.message!.trim());
      }
      throw Exception('No se pudo reintentar la factura (${e.code})');
    }
  }
}
