import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../providers/chat_providers.dart';
import 'chat_conversation_screen.dart';
import '../../../profile/presentation/providers/profile_provider.dart';

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

  String _getChatTitle(chat, String? currentUserId) {
    // Determine who is the "other" participant to show their name
    if (chat.type == ChatType.heroRider) {
      // Hero-Rider chat
      if (currentUserId == chat.buyerId) {
        // Current user is the buyer (hero), show rider name
        return chat.riderName ?? 'Rider';
      } else {
        // Current user is the rider, show buyer name
        return chat.buyerName ?? 'Cliente';
      }
    } else {
      // Hero-Seller chat (future implementation)
      return chat.buyerName ?? 'Vendedor';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chatsAsync = ref.watch(userChatsProvider);
    final profileAsync = ref.watch(profileProvider);

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Mensajes',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
        ),
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: chatsAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(color: primaryOrange),
          ),
          error: (error, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: textGray600.withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _friendlyError(error),
                    style: const TextStyle(color: textGray600, fontSize: 14),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
          data: (chats) {
            if (chats.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.chat_bubble_outline,
                        size: 64,
                        color: textGray600.withValues(alpha: 0.4),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No tienes chats aún',
                        style: TextStyle(
                          color: textGray900,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'Tus conversaciones aparecerán aquí',
                        style: TextStyle(color: textGray600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              );
            }

            final currentUserId = profileAsync.value?.id;

            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: chats.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final chat = chats[index];
                final subtitle = chat.lastMessageText.isEmpty
                    ? 'Sin mensajes'
                    : chat.lastMessageText;

                final participantName = _getChatTitle(chat, currentUserId);

                // Build title with participant name and order/offer number
                final String title;
                if (chat.orderId != null && chat.orderId!.isNotEmpty) {
                  final shortOrderId = chat.orderId!.length > 8
                      ? chat.orderId!.substring(0, 8)
                      : chat.orderId!;
                  title = '$participantName • Pedido #$shortOrderId';
                } else if (chat.offerId != null && chat.offerId!.isNotEmpty) {
                  final shortOfferId = chat.offerId!.length > 8
                      ? chat.offerId!.substring(0, 8)
                      : chat.offerId!;
                  title = '$participantName • Oferta #$shortOfferId';
                } else {
                  title = participantName;
                }

                final hasUnread = chat.unreadCount > 0;

                return Material(
                  key: ValueKey(chat.chatId),
                  color: backgroundWhite,
                  borderRadius: BorderRadius.circular(16),
                  elevation: 0,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatConversationScreen(chat: chat),
                        ),
                      );
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: hasUnread
                              ? primaryOrange.withValues(alpha: 0.3)
                              : borderGray100,
                          width: hasUnread ? 2 : 1,
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          children: [
                            Stack(
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: hasUnread
                                        ? primaryOrange.withValues(alpha: 0.18)
                                        : primaryOrange.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(14),
                                  ),
                                  child: Icon(
                                    chat.type == ChatType.heroRider
                                        ? Icons.delivery_dining
                                        : Icons.storefront,
                                    color: primaryOrange,
                                    size: 24,
                                  ),
                                ),
                                if (hasUnread)
                                  Positioned(
                                    right: 0,
                                    top: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(4),
                                      decoration: const BoxDecoration(
                                        color: primaryOrange,
                                        shape: BoxShape.circle,
                                      ),
                                      constraints: const BoxConstraints(
                                        minWidth: 18,
                                        minHeight: 18,
                                      ),
                                      child: Center(
                                        child: Text(
                                          chat.unreadCount > 99
                                              ? '99+'
                                              : chat.unreadCount.toString(),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    style: TextStyle(
                                      color: textGray900,
                                      fontWeight: hasUnread
                                          ? FontWeight.w800
                                          : FontWeight.w700,
                                      fontSize: 15,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    subtitle,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: hasUnread
                                          ? textGray900
                                          : textGray600,
                                      fontWeight: hasUnread
                                          ? FontWeight.w600
                                          : FontWeight.w500,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                              Icons.chevron_right,
                              color: textGray600.withValues(alpha: 0.6),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
