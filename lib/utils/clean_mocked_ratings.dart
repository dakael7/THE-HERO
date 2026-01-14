import 'package:cloud_firestore/cloud_firestore.dart';

/// Script de limpieza para resetear calificaciones mockeadas
///
/// INSTRUCCIONES:
/// 1. Llama a esta función desde algún lugar temporal en tu app
/// 2. Ejecuta la app una vez
/// 3. Elimina la llamada después de ejecutar
///
/// Ejemplo de uso:
/// ```dart
/// // En algún botón temporal o initState:
/// await cleanMockedRatings();
/// ```
Future<void> cleanMockedRatings() async {
  final firestore = FirebaseFirestore.instance;

  try {
    print('🧹 Iniciando limpieza de calificaciones mockeadas...');

    // Obtener todas las ofertas
    final offersSnapshot = await firestore.collection('offers').get();

    int updatedCount = 0;
    int skippedCount = 0;

    // Procesar cada oferta
    for (final doc in offersSnapshot.docs) {
      final data = doc.data();
      final avgRating = data['avgRating'] as num? ?? 0;
      final ratingCount = data['ratingCount'] as int? ?? 0;

      // Si tiene calificaciones, resetearlas
      if (avgRating > 0 || ratingCount > 0) {
        await doc.reference.update({'avgRating': 0.0, 'ratingCount': 0});

        updatedCount++;
        print(
          '✅ Limpiada oferta: ${doc.id} (rating: $avgRating, count: $ratingCount)',
        );
      } else {
        skippedCount++;
      }
    }

    print('');
    print('✨ Limpieza completada!');
    print('📊 Ofertas actualizadas: $updatedCount');
    print('⏭️  Ofertas omitidas (ya limpias): $skippedCount');
    print('📝 Total de ofertas: ${offersSnapshot.docs.length}');
  } catch (e, stackTrace) {
    print('❌ Error durante la limpieza: $e');
    print('Stack trace: $stackTrace');
    rethrow;
  }
}

/// Versión alternativa: Limpiar solo una oferta específica
Future<void> cleanSingleOffer(String offerId) async {
  final firestore = FirebaseFirestore.instance;

  try {
    await firestore.collection('offers').doc(offerId).update({
      'avgRating': 0.0,
      'ratingCount': 0,
    });

    print('✅ Oferta $offerId limpiada exitosamente');
  } catch (e) {
    print('❌ Error al limpiar oferta $offerId: $e');
    rethrow;
  }
}
