import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  final FocusNode _inputFocus = FocusNode();

  Timer? _typingStopTimer;
  DateTime? _lastTypingWriteAt;
  DateTime? _lastAutoReadAt;
  int _lastMessageCount = 0;
  bool _isAtBottom = true;
  bool _showScrollDown = false;

  // ── Helpers ─────────────────────────────────────────────────────────────────
  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('Usuario no autenticado')) {
      return 'Inicia sesión para ver mensajes.';
    }
    if (raw.contains('Chat bloqueado')) return 'Este chat está bloqueado.';
    if (error is FirebaseException) {
      if (error.code == 'permission-denied') {
        return 'Sin permisos para este chat.';
      }
      if (error.code == 'unavailable') return 'Sin conexión a internet.';
    }
    return 'Error al cargar los mensajes.';
  }

  String _formatTime(DateTime dt) => DateFormat('HH:mm').format(dt);

  String _formatDateHeader(DateTime dt) {
    const months = [
      'enero',
      'febrero',
      'marzo',
      'abril',
      'mayo',
      'junio',
      'julio',
      'agosto',
      'septiembre',
      'octubre',
      'noviembre',
      'diciembre',
    ];
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Hoy';
    if (diff == 1) return 'Ayer';
    return '${dt.day} de ${months[dt.month - 1]} ${dt.year}';
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
  }

  // ── Lifecycle ────────────────────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    FCMService().setActiveChatId(widget.chat.chatId);
    _scrollController.addListener(_onScroll);

    Future.microtask(() async {
      try {
        await ref.read(chatActionsProvider).ensureChatExists(widget.chat);
      } catch (_) {}
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(chatActionsProvider).markMessagesAsRead(widget.chat.chatId);
    });
  }

  @override
  void dispose() {
    _typingStopTimer?.cancel();
    _scrollController.removeListener(_onScroll);
    try {
      ref
          .read(chatActionsProvider)
          .setTyping(chatId: widget.chat.chatId, isTyping: false);
    } catch (_) {}
    FCMService().setActiveChatId(null);
    _controller.dispose();
    _scrollController.dispose();
    _inputFocus.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final current = _scrollController.position.pixels;
    final atBottom = (maxScroll - current) < 80;
    if (atBottom != _isAtBottom) {
      setState(() {
        _isAtBottom = atBottom;
        _showScrollDown = !atBottom;
      });
    }
  }

  void _scrollToBottom({bool animate = true}) {
    if (!_scrollController.hasClients) return;
    if (animate) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    } else {
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    }
  }

  void _onTextChanged(String value) {
    final currentUserId = ref.read(firebaseAuthProvider).currentUser?.uid;
    if (currentUserId == null || currentUserId.isEmpty) return;

    if (value.trim().isEmpty) {
      _typingStopTimer?.cancel();
      Future.microtask(() async {
        try {
          await ref
              .read(chatActionsProvider)
              .setTyping(chatId: widget.chat.chatId, isTyping: false);
        } catch (_) {}
      });
      return;
    }

    final now = DateTime.now();
    final last = _lastTypingWriteAt;
    if (last == null ||
        now.difference(last) > const Duration(milliseconds: 900)) {
      _lastTypingWriteAt = now;
      Future.microtask(() async {
        try {
          await ref
              .read(chatActionsProvider)
              .setTyping(chatId: widget.chat.chatId, isTyping: true);
        } catch (_) {}
      });
    }

    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), () {
      Future.microtask(() async {
        try {
          await ref
              .read(chatActionsProvider)
              .setTyping(chatId: widget.chat.chatId, isTyping: false);
        } catch (_) {}
      });
    });
  }

  void _maybeAutoMarkRead({
    required String? currentUserId,
    required List<ChatMessage> messages,
  }) {
    if (currentUserId == null || !mounted) return;
    final hasUnread = messages.any(
      (m) => m.senderId.isNotEmpty && m.senderId != currentUserId && !m.isRead,
    );
    if (!hasUnread) return;
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
    HapticFeedback.lightImpact();
    _controller.clear();
    try {
      await ref
          .read(chatActionsProvider)
          .setTyping(chatId: widget.chat.chatId, isTyping: false);
    } catch (_) {}
    try {
      await ref
          .read(chatActionsProvider)
          .sendTextMessage(chatId: widget.chat.chatId, text: text);
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_friendlyError(e)),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final currentUserId = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final typingAsync = ref.watch(chatTypingProvider(widget.chat.chatId));
    final orderId = widget.chat.orderId?.trim();
    final orderAsync = orderId != null && orderId.isNotEmpty
        ? ref.watch(orderByIdProvider(orderId))
        : null;
    final order = orderAsync?.value;
    final isChatLocked =
        orderAsync != null &&
        (order == null ||
            order.status.isCompleted ||
            !order.canShowAssociatedChats);

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
    final offerFuture = (offerId != null && offerId.isNotEmpty)
        ? ref.read(offersRepositoryProvider).getOfferById(offerId)
        : null;

    String participantName;
    if (isBuyer) {
      participantName = widget.chat.type == ChatType.heroRider
          ? (widget.chat.riderName ?? 'Rider')
          : (sellerAsync?.value?.fullName ?? 'Vendedor');
    } else if (isRider) {
      participantName = widget.chat.buyerName ?? 'Cliente';
    } else {
      participantName = widget.chat.type == ChatType.heroRider
          ? (widget.chat.riderName ?? 'Rider')
          : (widget.chat.buyerName ?? 'Cliente');
    }

    final contextLabel =
        (widget.chat.orderId != null && widget.chat.orderId!.isNotEmpty)
        ? 'Pedido #${widget.chat.orderId!.length > 8 ? widget.chat.orderId!.substring(0, 8).toUpperCase() : widget.chat.orderId!.toUpperCase()}'
        : (widget.chat.offerId != null && widget.chat.offerId!.isNotEmpty)
        ? 'Oferta #${widget.chat.offerId!.length > 8 ? widget.chat.offerId!.substring(0, 8).toUpperCase() : widget.chat.offerId!.toUpperCase()}'
        : (widget.chat.type == ChatType.heroRider
              ? 'Chat con Rider'
              : 'Chat con Vendedor');

    // Who is the other participant?
    final otherUserId = (() {
      final me = currentUserId;
      if (me == null || me.isEmpty) return null;
      if (widget.chat.type == ChatType.heroRider) {
        return me == widget.chat.buyerId
            ? widget.chat.riderId
            : widget.chat.buyerId;
      }
      return me == widget.chat.buyerId
          ? widget.chat.sellerId
          : widget.chat.buyerId;
    })();

    final otherUserAsync = otherUserId == null
        ? const AsyncValue<User?>.data(null)
        : ref.watch(userByIdProvider(otherUserId));
    final otherUserPhotoUrl = otherUserAsync.maybeWhen(
      data: (u) => u?.profilePhotoUrl,
      orElse: () => null,
    );
    final hasPhoto = (otherUserPhotoUrl ?? '').trim().isNotEmpty;

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

    return FutureBuilder<Offer?>(
      future: offerFuture,
      builder: (context, offerSnap) {
        final offerTitle = offerSnap.data?.title;
        final subtitle = isOtherTyping
            ? 'Escribiendo...'
            : (offerTitle != null && offerTitle.trim().isNotEmpty
                  ? '$contextLabel • $offerTitle'
                  : contextLabel);

        return Scaffold(
          backgroundColor: const Color(0xFFF0F2F5),
          appBar: _buildAppBar(
            participantName: participantName,
            subtitle: subtitle,
            isTyping: isOtherTyping,
            hasPhoto: hasPhoto,
            photoUrl: otherUserPhotoUrl,
          ),
          body: Stack(
            children: [
              Column(
                children: [
                  Expanded(
                    child: Builder(
                      builder: (context) {
                        final messagesAsync = ref.watch(
                          chatMessagesProvider(widget.chat.chatId),
                        );
                        return messagesAsync.when(
                          loading: () => const Center(
                            child: CircularProgressIndicator(
                              color: primaryOrange,
                            ),
                          ),
                          error: (error, _) => Center(
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                _friendlyError(error),
                                style: const TextStyle(color: textGray600),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          data: (messages) {
                            _maybeAutoMarkRead(
                              currentUserId: currentUserId,
                              messages: messages,
                            );
                            if (messages.length != _lastMessageCount) {
                              _lastMessageCount = messages.length;
                              if (_isAtBottom) {
                                WidgetsBinding.instance.addPostFrameCallback(
                                  (_) => _scrollToBottom(animate: false),
                                );
                              }
                            }
                            if (messages.isEmpty) {
                              return _EmptyChat(
                                participantName: participantName,
                              );
                            }
                            return _MessageList(
                              messages: messages,
                              currentUserId: currentUserId,
                              chat: widget.chat,
                              sellerAsync: sellerAsync,
                              scrollController: _scrollController,
                              formatTime: _formatTime,
                              formatDateHeader: _formatDateHeader,
                              initials: _initials,
                            );
                          },
                        );
                      },
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: _InputArea(
                      controller: _controller,
                      focusNode: _inputFocus,
                      isLocked: isChatLocked,
                      onChanged: _onTextChanged,
                      onSend: _send,
                    ),
                  ),
                ],
              ),

              // ── Scroll-to-bottom FAB ────────────────────────────────────
              if (_showScrollDown)
                Positioned(
                  bottom: 80,
                  right: 16,
                  child: GestureDetector(
                    onTap: () => _scrollToBottom(),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: primaryOrange,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: primaryOrange.withValues(alpha: 0.4),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: Colors.white,
                        size: 22,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar({
    required String participantName,
    required String subtitle,
    required bool isTyping,
    required bool hasPhoto,
    required String? photoUrl,
  }) {
    return AppBar(
      backgroundColor: primaryOrange,
      foregroundColor: Colors.white,
      elevation: 0,
      titleSpacing: 0,
      leadingWidth: 44,
      leading: IconButton(
        icon: const Icon(
          Icons.arrow_back_ios_new_rounded,
          size: 18,
          color: Colors.white,
        ),
        onPressed: () => Navigator.of(context).pop(),
      ),
      title: Row(
        children: [
          // Avatar
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.4)),
            ),
            alignment: Alignment.center,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: hasPhoto
                  ? Image.network(
                      photoUrl!.trim(),
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => Text(
                        _initials(participantName),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                          fontSize: 14,
                        ),
                      ),
                    )
                  : Text(
                      _initials(participantName),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  participantName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                  ),
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  child: Text(
                    subtitle,
                    key: ValueKey(subtitle),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.85),
                      fontWeight: FontWeight.w500,
                      fontStyle: isTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Message List ────────────────────────────────────────────────────────────
class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.currentUserId,
    required this.chat,
    required this.sellerAsync,
    required this.scrollController,
    required this.formatTime,
    required this.formatDateHeader,
    required this.initials,
  });

  final List<ChatMessage> messages;
  final String? currentUserId;
  final Chat chat;
  final AsyncValue<User?>? sellerAsync;
  final ScrollController scrollController;
  final String Function(DateTime) formatTime;
  final String Function(DateTime) formatDateHeader;
  final String Function(String) initials;

  @override
  Widget build(BuildContext context) {
    // Build list with date headers
    final items = <dynamic>[];
    DateTime? lastDate;
    for (final msg in messages) {
      final day = DateTime(msg.sentAt.year, msg.sentAt.month, msg.sentAt.day);
      if (lastDate == null || day != lastDate) {
        items.add(day);
        lastDate = day;
      }
      items.add(msg);
    }

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        if (item is DateTime) {
          return _DateHeader(label: formatDateHeader(item));
        }
        final message = item as ChatMessage;
        final isMe = currentUserId != null && message.senderId == currentUserId;
        final senderName = isMe
            ? 'Tú'
            : (message.senderId == chat.buyerId
                  ? (chat.buyerName ?? 'Cliente')
                  : (chat.type == ChatType.heroRider
                        ? (chat.riderName ?? 'Rider')
                        : (sellerAsync?.value?.fullName ?? 'Vendedor')));

        // Check if next message is from same sender (for tail logic)
        final nextItem = index < items.length - 1 ? items[index + 1] : null;
        final nextMsg = nextItem is ChatMessage ? nextItem : null;
        final isLastInGroup =
            nextMsg == null || nextMsg.senderId != message.senderId;

        return _MessageBubble(
          key: ValueKey(message.messageId),
          message: message,
          isMe: isMe,
          senderName: senderName,
          isLastInGroup: isLastInGroup,
          formatTime: formatTime,
          senderInitials: initials(senderName),
        );
      },
    );
  }
}

// ─── Date Header ─────────────────────────────────────────────────────────────
class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          const Expanded(
            child: Divider(color: Color(0xFFE5E7EB), thickness: 1),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: textGray600,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          const Expanded(
            child: Divider(color: Color(0xFFE5E7EB), thickness: 1),
          ),
        ],
      ),
    );
  }
}

// ─── Message Bubble ──────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.senderName,
    required this.isLastInGroup,
    required this.formatTime,
    required this.senderInitials,
  });

  final ChatMessage message;
  final bool isMe;
  final String senderName;
  final bool isLastInGroup;
  final String Function(DateTime) formatTime;
  final String senderInitials;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: EdgeInsets.only(
        bottom: isLastInGroup ? 8 : 2,
        left: isMe ? 48 : 0,
        right: isMe ? 0 : 48,
      ),
      child: Row(
        mainAxisAlignment: isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // Other user's avatar (only on last in group)
          if (!isMe) ...[
            if (isLastInGroup)
              Container(
                width: 28,
                height: 28,
                margin: const EdgeInsets.only(right: 6, bottom: 2),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [primaryOrange, Color(0xFFFF9800)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                alignment: Alignment.center,
                child: Text(
                  senderInitials,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              )
            else
              const SizedBox(width: 34),
          ],

          // Bubble
          Flexible(
            child: Container(
              constraints: BoxConstraints(maxWidth: screenWidth * 0.72),
              padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(
                        colors: [primaryOrange, Color(0xFFFF9800)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isMe ? null : Colors.white,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: isMe
                      ? const Radius.circular(16)
                      : (isLastInGroup
                            ? const Radius.circular(4)
                            : const Radius.circular(16)),
                  bottomRight: isMe
                      ? (isLastInGroup
                            ? const Radius.circular(4)
                            : const Radius.circular(16))
                      : const Radius.circular(16),
                ),
                boxShadow: [
                  BoxShadow(
                    color: isMe
                        ? primaryOrange.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isMe)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
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
                      color: isMe ? Colors.white : textGray900,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        formatTime(message.sentAt),
                        style: TextStyle(
                          color: isMe
                              ? Colors.white.withValues(alpha: 0.75)
                              : textGray600,
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (isMe) ...[
                        const SizedBox(width: 3),
                        Icon(
                          message.isRead ? Icons.done_all : Icons.done,
                          size: 13,
                          color: message.isRead
                              ? const Color(0xFF93C5FD)
                              : Colors.white.withValues(alpha: 0.75),
                        ),
                      ],
                    ],
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

// ─── Empty Chat ───────────────────────────────────────────────────────────────
class _EmptyChat extends StatelessWidget {
  const _EmptyChat({required this.participantName});
  final String participantName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryOrange.withValues(alpha: 0.15),
                    primaryOrange.withValues(alpha: 0.05),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.waving_hand_rounded,
                color: primaryOrange,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '¡Saluda a $participantName!',
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textGray900,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            const Text(
              'Sé el primero en escribir un mensaje',
              style: TextStyle(color: textGray600, fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Input Area ───────────────────────────────────────────────────────────────
class _InputArea extends StatefulWidget {
  const _InputArea({
    required this.controller,
    required this.focusNode,
    required this.isLocked,
    required this.onChanged,
    required this.onSend,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isLocked;
  final void Function(String) onChanged;
  final Future<void> Function() onSend;

  @override
  State<_InputArea> createState() => _InputAreaState();
}

class _InputAreaState extends State<_InputArea> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  void _onControllerChanged() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText) setState(() => _hasText = has);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isLocked) {
      return Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF9FAFB),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE5E7EB)),
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lock_outline_rounded, color: textGray600, size: 16),
              SizedBox(width: 8),
              Text(
                'Chat bloqueado — pedido cerrado',
                style: TextStyle(
                  color: textGray600,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(maxHeight: 120),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: TextField(
                controller: widget.controller,
                focusNode: widget.focusNode,
                textInputAction: TextInputAction.newline,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                onChanged: widget.onChanged,
                style: const TextStyle(
                  color: textGray900,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w400,
                ),
                decoration: const InputDecoration(
                  hintText: 'Escribe un mensaje...',
                  hintStyle: TextStyle(color: textGray600, fontSize: 14),
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          AnimatedScale(
            scale: _hasText ? 1.0 : 0.85,
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            child: GestureDetector(
              onTap: _hasText ? widget.onSend : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  gradient: _hasText
                      ? const LinearGradient(
                          colors: [primaryOrange, Color(0xFFFF9800)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        )
                      : const LinearGradient(
                          colors: [Color(0xFFD1D5DB), Color(0xFFE5E7EB)],
                        ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: _hasText
                      ? [
                          BoxShadow(
                            color: primaryOrange.withValues(alpha: 0.35),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          ),
                        ]
                      : null,
                ),
                alignment: Alignment.center,
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
