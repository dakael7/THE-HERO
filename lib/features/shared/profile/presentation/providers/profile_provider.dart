import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:the_hero/data/providers/repository_providers.dart';
import 'package:the_hero/data/providers/network_providers.dart';
import 'package:the_hero/domain/entities/user.dart';
import 'package:the_hero/data/models/user_model.dart';
import 'package:the_hero/data/mappers/user_mapper.dart';

User _mapUserSnapshot({
  required String userId,
  required Map<String, dynamic>? data,
}) {
  if (data == null) {
    throw StateError('Documento de usuario vacío para uid=$userId');
  }
  final model = UserModel.fromJson({'id': userId, ...data});
  return UserMapper.toEntity(model);
}

final currentUserIdProvider = Provider<String?>((ref) {
  final currentUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
  if (currentUid != null && currentUid.isNotEmpty) {
    return currentUid;
  }

  final authAsync = ref.watch(firebaseAuthUserProvider);
  final liveUid = authAsync.value?.uid;
  if (liveUid != null && liveUid.isNotEmpty) {
    return liveUid;
  }

  return null;
});

final profileProvider = FutureProvider<User?>((ref) async {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null) return null;

  try {
    final firestore = ref.read(firebaseFirestoreProvider);
    final doc = await firestore
        .collection('users')
        .doc(uid)
        .get(const GetOptions(source: Source.server))
        .timeout(const Duration(seconds: 4));
    if (!doc.exists) return null;
    return _mapUserSnapshot(userId: uid, data: doc.data());
  } catch (e) {
    print('Error al cargar perfil: $e');
    return null;
  }
});

final profileStreamProvider = StreamProvider<User?>((ref) {
  final uid = ref.watch(currentUserIdProvider);
  if (uid == null || uid.trim().isEmpty) {
    return Stream.value(null);
  }

  final firestore = ref.watch(firebaseFirestoreProvider);
  final userDoc = firestore.collection('users').doc(uid);
  final controller = StreamController<User?>();

  Future<void> emitInitialUser() async {
    try {
      final firstDoc = await userDoc
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 2));
      if (!controller.isClosed) {
        if (!firstDoc.exists) {
          controller.add(null);
        } else {
          controller.add(_mapUserSnapshot(userId: uid, data: firstDoc.data()));
        }
      }
    } catch (e) {
      print('Error al obtener perfil inicial: $e');
      if (!controller.isClosed) {
        controller.addError(e);
      }
    }
  }

  unawaited(emitInitialUser());

  final sub = userDoc.snapshots().listen(
    (snap) {
      if (controller.isClosed) return;
      if (!snap.exists) {
        controller.add(null);
        return;
      }
      try {
        controller.add(_mapUserSnapshot(userId: uid, data: snap.data()));
      } catch (e) {
        controller.addError(e);
      }
    },
    onError: (e) {
      print('Error en stream de perfil: $e');
      if (!controller.isClosed) {
        controller.addError(e);
      }
    },
  );

  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });

  return controller.stream;
});

final userByIdStreamProvider =
    StreamProvider.family<User?, String>((ref, userId) {
  if (userId.trim().isEmpty) return const Stream<User?>.empty();

  final firestore = ref.watch(firebaseFirestoreProvider);
  return firestore.collection('users').doc(userId).snapshots().map((snap) {
    if (!snap.exists) return null;
    final data = snap.data();
    if (data == null) return null;
    final model = UserModel.fromJson({'id': userId, ...data});
    return UserMapper.toEntity(model);
  });
});

final userByIdProvider =
    FutureProvider.family<User?, String>((ref, userId) async {
  try {
    final authRepository = ref.read(authRepositoryProvider);
    return await authRepository.getUserById(userId);
  } catch (e) {
    print('Error al cargar usuario por id: $e');
    return null;
  }
});
