import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../providers/chat_providers.dart';
import 'chat_conversation_screen.dart';

class ChatListScreen extends ConsumerWidget {
  const ChatListScreen({super.key});

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('Usuario no autenticado')) {
      return 'Inicia sesión para ver tus mensajes.';
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'No tienes permisos para ver tus mensajes.\nRevisa sesión y reglas de Firestore.';
      }
      if (error.code == 'unavailable') {
        return 'Servicio no disponible. Revisa tu conexión a internet.';
      }
    }
    return 'Ocurrió un error al cargar los mensajes.';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(userChatsProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        title: const Text('Chats'),
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
      ),
      body: chatsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (error, _) => Center(
          child: Text(
            _friendlyError(error),
            style: const TextStyle(color: textGray600),
            textAlign: TextAlign.center,
          ),
        ),
        data: (chats) {
          if (chats.isEmpty) {
            return const Center(
              child: Text(
                'No tienes chats aún',
                style: TextStyle(color: textGray600),
              ),
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: chats.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final chat = chats[index];
              final subtitle =
                  chat.lastMessageText.isEmpty ? 'Sin mensajes' : chat.lastMessageText;

              final title = chat.type == ChatType.heroRider
                  ? 'Chat con Rider'
                  : 'Chat con Vendedor';

              return Material(
                color: backgroundWhite,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ChatConversationScreen(chat: chat),
                      ),
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: primaryOrange.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Icon(
                            chat.type == ChatType.heroRider
                                ? Icons.delivery_dining
                                : Icons.storefront,
                            color: primaryOrange,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  color: textGray900,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: textGray600,
                                  fontWeight: FontWeight.w500,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right, color: textGray600),
                      ],
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
