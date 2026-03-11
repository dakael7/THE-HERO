import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:intl/intl.dart';
import 'dart:async';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../core/services/fcm_service.dart';
import '../../../../../data/providers/network_providers.dart';
import '../../../../../data/providers/repository_providers.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../../../../../domain/entities/chat_message.dart';
import '../../../../../domain/entities/offer.dart';
import '../../../../../domain/entities/order_status.dart';
import '../../../../../domain/entities/user.dart';
import '../../../../orders/presentation/providers/orders_provider.dart';
import '../../../profile/presentation/providers/profile_provider.dart';
import '../providers/chat_providers.dart';

class ChatConversationScreen extends ConsumerStatefulWidget {
  final Chat chat;

  const ChatConversationScreen({super.key, required this.chat});

  @override
  ConsumerState<ChatConversationScreen> createState() =>
      _ChatConversationScreenState();
}

class _ChatConversationScreenState
    extends ConsumerState<ChatConversationScreen> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  Timer? _typingStopTimer;
  DateTime? _lastTypingWriteAt;

  DateTime? _lastAutoReadAt;
  int _lastMessageCount = 0;

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('Usuario no autenticado')) {
      return 'Inicia sesión para ver y enviar mensajes.';
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'No tienes permisos para ver este chat.';
      }
      if (error.code == 'unavailable') {
        return 'Servicio no disponible. Revisa tu conexión a internet.';
      }
    }
    return 'Ocurrió un error al cargar los mensajes.';
  }

  String _formatTimestamp(DateTime dateTime) {
    final formatter = DateFormat('MMM dd, HH:mm');
    return formatter.format(dateTime);
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters.take(1).toString();
    return (parts[0].characters.take(1).toString() +
            parts[1].characters.take(1).toString())
        .toUpperCase();
  }

  @override
  void initState() {
    super.initState();
    FCMService().setActiveChatId(widget.chat.chatId);
    // Ensure chat exists in background without blocking UI
    Future.microtask(() async {
      try {
        await ref.read(chatActionsProvider).ensureChatExists(widget.chat);
      } catch (_) {
        // Silently ignore - chat may already exist or will be created on first message
      }
    });

    // Mark messages as read when opening the conversation
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatActionsProvider).markMessagesAsRead(widget.chat.chatId);
    });
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    try {
      ref.read(chatActionsProvider).setTyping(
            chatId: widget.chat.chatId,
            isTyping: false,
          );
    } catch (_) {
      // ignore
    }
    FCMService().setActiveChatId(null);
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onTextChanged(String value) {
    final currentUserId = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return;

    final trimmed = value.trim();

    // If user cleared input, stop typing immediately.
    if (trimmed.isEmpty) {
      _typingStopTimer?.cancel();
      Future.microtask(() async {
        try {
          await ref.read(chatActionsProvider).setTyping(
                chatId: widget.chat.chatId,
                isTyping: false,
              );
        } catch (_) {
          // ignore
        }
      });
      return;
    }

    // Throttle writes to Firestore.
    final now = DateTime.now();
    final last = _lastTypingWriteAt;
    if (last == null || now.difference(last) > const Duration(milliseconds: 900)) {
      _lastTypingWriteAt = now;
      Future.microtask(() async {
        try {
          await ref.read(chatActionsProvider).setTyping(
                chatId: widget.chat.chatId,
                isTyping: true,
              );
        } catch (_) {
          // ignore
        }
      });
    }

    // Stop typing after inactivity.
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      Future.microtask(() async {
        try {
          await ref.read(chatActionsProvider).setTyping(
                chatId: widget.chat.chatId,
                isTyping: false,
              );
        } catch (_) {
          // ignore
        }
      });
    });
  }

  void _maybeAutoMarkRead({
    required String? currentUserId,
    required List<ChatMessage> messages,
  }) {
    if (currentUserId == null) return;
    if (!mounted) return;

    final hasUnreadFromOther = messages.any((m) {
      final senderId = m.senderId;
      if (senderId.isEmpty || senderId == currentUserId) return false;
      return !m.isRead;
    });

    if (!hasUnreadFromOther) return;

    final now = DateTime.now();
    final last = _lastAutoReadAt;
    if (last != null && now.difference(last) < const Duration(seconds: 2)) {
      return;
    }
    _lastAutoReadAt = now;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(chatActionsProvider).markMessagesAsRead(widget.chat.chatId);
    });
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;

    _controller.clear();
    try {
      await ref.read(chatActionsProvider).setTyping(
            chatId: widget.chat.chatId,
            isTyping: false,
          );
    } catch (_) {
      // ignore
    }
    final actions = ref.read(chatActionsProvider);
    try {
      await actions.sendTextMessage(chatId: widget.chat.chatId, text: text);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderId = widget.chat.orderId;
    final orderAsync = orderId != null && orderId.isNotEmpty
        ? ref.watch(orderByIdProvider(orderId))
        : null;
    final isOrderCompleted = orderAsync?.when(
          data: (order) => order?.status == OrderStatus.delivered,
          loading: () => false,
          error: (_, __) => false,
        ) ?? false;

    final currentUserId = ref.watch(firebaseAuthProvider).currentUser?.uid;

    final typingAsync = ref.watch(chatTypingProvider(widget.chat.chatId));

    final isBuyer =
        currentUserId != null && currentUserId == widget.chat.buyerId;
    final isRider =
        currentUserId != null && currentUserId == widget.chat.riderId;

    final sellerId = widget.chat.sellerId;
    final sellerAsync =
        (widget.chat.type == ChatType.heroSeller && sellerId != null)
        ? ref.watch(userByIdProvider(sellerId))
        : null;

    final offerId = widget.chat.offerId;
    final offerTitleFuture = (offerId != null && offerId.isNotEmpty)
        ? ref.read(offersRepositoryProvider).getOfferById(offerId)
        : null;

    String participantName;
    if (isBuyer) {
      // Buyer sees: rider name (heroRider) or seller name (heroSeller)
      participantName = widget.chat.type == ChatType.heroRider
          ? (widget.chat.riderName ?? 'Rider')
          : (sellerAsync?.value?.fullName ?? 'Vendedor');
    } else if (isRider) {
      // Rider always sees the buyer name
      participantName = widget.chat.buyerName ?? 'Cliente';
    } else {
      // Seller: heroRider chat → show rider; heroSeller chat → show buyer
      participantName = widget.chat.type == ChatType.heroRider
          ? (widget.chat.riderName ?? 'Rider')
          : (widget.chat.buyerName ?? 'Cliente');
    }

    final contextLabel =
        (widget.chat.orderId != null && widget.chat.orderId!.isNotEmpty)
        ? 'Pedido #${widget.chat.orderId!.length > 8 ? widget.chat.orderId!.substring(0, 8) : widget.chat.orderId}'
        : (widget.chat.offerId != null && widget.chat.offerId!.isNotEmpty)
        ? 'Oferta #${widget.chat.offerId!.length > 8 ? widget.chat.offerId!.substring(0, 8) : widget.chat.offerId}'
        : (widget.chat.type == ChatType.heroRider
              ? 'Chat con Rider'
              : 'Chat con Vendedor');

    return FutureBuilder<Offer?>(
      future: offerTitleFuture,
      builder: (context, offerSnap) {
        final offerTitle = offerSnap.data?.title;
        final baseSubtitle = (offerTitle != null && offerTitle.trim().isNotEmpty)
            ? '$contextLabel • $offerTitle'
            : contextLabel;

        final otherUserId = (() {
          final me = currentUserId;
          if (me == null || me.trim().isEmpty) return null;

          if (widget.chat.type == ChatType.heroRider) {
            if (me == widget.chat.buyerId) return widget.chat.riderId;
            return widget.chat.buyerId;
          }

          // hero_seller
          if (me == widget.chat.buyerId) return widget.chat.sellerId;
          return widget.chat.buyerId;
        })();

        final otherUserAsync = otherUserId == null
            ? const AsyncValue<User?>.data(null)
            : ref.watch(userByIdProvider(otherUserId));
        final otherUserPhotoUrl = otherUserAsync.maybeWhen(
          data: (u) => u?.profilePhotoUrl,
          orElse: () => null,
        );
        final hasOtherPhoto =
            (otherUserPhotoUrl ?? '').trim().isNotEmpty;

        final isOtherTyping = typingAsync.maybeWhen(
          data: (map) {
            if (otherUserId == null) return false;
            final lastTypedAt = map[otherUserId];
            if (lastTypedAt == null) return false;
            return DateTime.now().difference(lastTypedAt) <
                const Duration(seconds: 5);
          },
          orElse: () => false,
        );

        final subtitle = isOtherTyping ? 'Escribiendo...' : baseSubtitle;

        return Scaffold(
          backgroundColor: backgroundGray50,
          appBar: AppBar(
            titleSpacing: 0,
            title: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  margin: const EdgeInsets.only(right: 10),
                  decoration: BoxDecoration(
                    color: primaryOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.8)),
                  ),
                  alignment: Alignment.center,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: hasOtherPhoto
                        ? Image.network(
                            otherUserPhotoUrl!.trim(),
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Text(
                                _initials(participantName),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: primaryOrange,
                                ),
                              );
                            },
                          )
                        : Text(
                            _initials(participantName),
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              color: primaryOrange,
                            ),
                          ),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        participantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12,
                          color: textGray600,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: primaryYellow,
            foregroundColor: textGray900,
          ),
          body: Builder(
            builder: (context) {
              final messagesAsync = ref.watch(
                chatMessagesProvider(widget.chat.chatId),
              );

              return Column(
                children: [
                  Expanded(
                    child: messagesAsync.when(
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
                      data: (messages) {
                        _maybeAutoMarkRead(
                          currentUserId: currentUserId,
                          messages: messages,
                        );

                        final shouldAutoScroll =
                            messages.length != _lastMessageCount;
                        _lastMessageCount = messages.length;
                        if (shouldAutoScroll) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (_scrollController.hasClients) {
                              _scrollController.jumpTo(
                                _scrollController.position.maxScrollExtent,
                              );
                            }
                          });
                        }

                        return ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final message = messages[index];
                            final isMe =
                                currentUserId != null &&
                                message.senderId == currentUserId;

                            // Determine sender name
                            final senderName = isMe
                                ? 'Tú'
                                : (message.senderId == widget.chat.buyerId
                                      ? (widget.chat.buyerName ?? 'Cliente')
                                      : (widget.chat.type == ChatType.heroRider
                                            ? (widget.chat.riderName ?? 'Rider')
                                            : (sellerAsync?.value?.fullName ??
                                                  'Vendedor')));

                            return Align(
                              key: ValueKey(message.messageId),
                              alignment: isMe
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.78,
                                ),
                                decoration: BoxDecoration(
                                  color: isMe ? primaryOrange : backgroundWhite,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: isMe
                                        ? primaryOrange.withValues(alpha: 0.28)
                                        : borderGray100,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withValues(alpha: 0.04),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (!isMe)
                                      Padding(
                                        padding: const EdgeInsets.only(
                                          bottom: 4,
                                        ),
                                        child: Text(
                                          senderName,
                                          style: const TextStyle(
                                            color: primaryOrange,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                      ),
                                    Text(
                                      message.text,
                                      style: TextStyle(
                                        color: isMe ? backgroundWhite : textGray900,
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          _formatTimestamp(message.sentAt),
                                          style: TextStyle(
                                            color: isMe
                                                ? backgroundWhite.withValues(alpha: 0.85)
                                                : textGray600,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                        if (isMe) ...[
                                          const SizedBox(width: 4),
                                          Icon(
                                            message.isRead
                                                ? Icons.done_all
                                                : Icons.done,
                                            size: 14,
                                            color: message.isRead
                                                ? const Color(0xFF0EA5E9)
                                                : backgroundWhite.withValues(alpha: 0.85),
                                          ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: _buildMessageInputArea(isOrderCompleted),
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildMessageInputArea(bool isOrderCompleted) {
    if (isOrderCompleted) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: BoxDecoration(
          color: backgroundWhite,
          border: Border(top: BorderSide(color: borderGray100)),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: backgroundGray50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderGray100),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.lock_outline,
                color: textGray600,
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Chat bloqueado - Pedido completado',
                style: TextStyle(
                  color: textGray600,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      decoration: BoxDecoration(
        color: backgroundWhite,
        border: Border(top: BorderSide(color: borderGray100)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.send,
              onChanged: _onTextChanged,
              onSubmitted: (_) {
                _send();
              },
              decoration: InputDecoration(
                hintText: 'Escribe un mensaje...',
                filled: true,
                fillColor: backgroundGray50,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
                prefixIcon: const Icon(
                  Icons.chat_bubble_outline,
                  color: textGray600,
                  size: 20,
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 46,
            height: 46,
            child: ElevatedButton(
              onPressed: () {
                _send();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryOrange,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                elevation: 0,
              ),
              child: const Icon(
                Icons.send,
                color: backgroundWhite,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
