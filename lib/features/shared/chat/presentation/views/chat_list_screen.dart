import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../../../../core/constants/app_colors.dart';
import '../../../../../domain/entities/chat.dart';
import '../../../../../domain/entities/chat_type.dart';
import '../providers/chat_providers.dart';
import 'chat_conversation_screen.dart';
import '../../../profile/presentation/providers/profile_provider.dart';

class _ChatGroup {
  final String groupKey;
  final String groupLabel;
  final DateTime lastActivity;
  final List<Chat> chats;

  _ChatGroup({
    required this.groupKey,
    required this.groupLabel,
    required this.lastActivity,
    required this.chats,
  });
}

List<_ChatGroup> _buildGroups(List<Chat> chats) {
  final Map<String, List<Chat>> buckets = {};

  for (final c in chats) {
    final key = (c.orderId != null && c.orderId!.isNotEmpty)
        ? 'order_${c.orderId}'
        : (c.offerId != null && c.offerId!.isNotEmpty)
        ? 'offer_${c.offerId}'
        : 'chat_${c.chatId}';
    buckets.putIfAbsent(key, () => []).add(c);
  }

  final groups = buckets.entries.map((entry) {
    final groupChats = entry.value
      ..sort((a, b) {
        final ta = a.lastMessageAt ?? a.updatedAt;
        final tb = b.lastMessageAt ?? b.updatedAt;
        return tb.compareTo(ta);
      });

    final lastActivity = groupChats
        .map((c) => c.lastMessageAt ?? c.updatedAt)
        .reduce((a, b) => a.isAfter(b) ? a : b);

    final firstChat = groupChats.first;
    String label;
    if (firstChat.orderId != null && firstChat.orderId!.isNotEmpty) {
      final short = firstChat.orderId!.length > 8
          ? firstChat.orderId!.substring(0, 8).toUpperCase()
          : firstChat.orderId!.toUpperCase();
      label = 'Pedido #$short';
    } else if (firstChat.offerId != null && firstChat.offerId!.isNotEmpty) {
      final short = firstChat.offerId!.length > 8
          ? firstChat.offerId!.substring(0, 8).toUpperCase()
          : firstChat.offerId!.toUpperCase();
      label = 'Oferta #$short';
    } else {
      label = 'Conversación';
    }

    return _ChatGroup(
      groupKey: entry.key,
      groupLabel: label,
      lastActivity: lastActivity,
      chats: groupChats,
    );
  }).toList()..sort((a, b) => b.lastActivity.compareTo(a.lastActivity));

  return groups;
}

// ─── Helpers ─────────────────────────────────────────────────────────────────
const _shortMonths = [
  'Ene','Feb','Mar','Abr','May','Jun',
  'Jul','Ago','Sep','Oct','Nov','Dic',
];

String _relativeTime(DateTime dt) {
  final now = DateTime.now();
  final diff = now.difference(dt);
  if (diff.inSeconds < 60) return 'Ahora';
  if (diff.inMinutes < 60) return 'Hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'Hace ${diff.inHours} h';
  if (diff.inDays == 1) return 'Ayer';
  if (diff.inDays < 7) return 'Hace ${diff.inDays} días';
  return '${dt.day} ${_shortMonths[dt.month - 1]}';
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

// ─── Main Widget ─────────────────────────────────────────────────────────────
class ChatListScreen extends ConsumerStatefulWidget {
  const ChatListScreen({super.key});

  @override
  ConsumerState<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends ConsumerState<ChatListScreen> {
  bool _isNavigating = false;

  String _friendlyError(Object error) {
    final raw = error.toString();
    if (raw.contains('Usuario no autenticado')) {
      return 'Inicia sesión para ver tus mensajes.';
    }
    if (error is FirebaseException) {
      if (error.code == 'permission-denied')
        return 'Sin permisos para ver mensajes.';
      if (error.code == 'unavailable') return 'Sin conexión a internet.';
    }
    return 'Error al cargar los mensajes.';
  }

  String _chatTitle(Chat chat, String? currentUserId) {
    if (chat.type == ChatType.heroRider) {
      return currentUserId == chat.buyerId
          ? (chat.riderName ?? 'Rider')
          : (chat.buyerName ?? 'Cliente');
    }
    return chat.buyerName ?? 'Vendedor';
  }

  String _chatRoleLabel(Chat chat) {
    switch (chat.type) {
      case ChatType.heroRider:
        return 'Con Rider';
      case ChatType.heroSeller:
        return 'Con Vendedor';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chatsAsync = ref.watch(userChatsProvider);
    final profileAsync = ref.watch(profileProvider);
    final currentUserId = profileAsync.value?.id;

    return Scaffold(
      backgroundColor: backgroundGray50,
      body: CustomScrollView(
        slivers: [
          // ── Premium AppBar ────────────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 110,
            pinned: true,
            backgroundColor: primaryOrange,
            foregroundColor: Colors.white,
            automaticallyImplyLeading: false,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [primaryOrange, Color(0xFFFF9800)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Stack(
                  children: [
                    // Decorative circles
                    Positioned(
                      top: -20,
                      right: -30,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 10,
                      left: -20,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    // Title
                    Positioned(
                      left: 20,
                      bottom: 16,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Mensajes',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                            ),
                          ),
                          chatsAsync.maybeWhen(
                            data: (chats) {
                              final total = chats.fold<int>(
                                0,
                                (s, c) => s + c.unreadCount,
                              );
                              if (total == 0) return const SizedBox.shrink();
                              return Text(
                                '$total sin leer',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            },
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      ),
                    ),
                    // Back button
                    Positioned(
                      right: 16,
                      bottom: 14,
                      child: GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.close,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          chatsAsync.when(
            loading: () => const SliverFillRemaining(
              child: Center(
                child: CircularProgressIndicator(color: primaryOrange),
              ),
            ),
            error: (error, _) => SliverFillRemaining(
              child: _ErrorState(message: _friendlyError(error)),
            ),
            data: (chats) {
              if (chats.isEmpty) {
                return const SliverFillRemaining(child: _EmptyState());
              }

              final groups = _buildGroups(chats);

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, i) {
                  final group = groups[i];
                  return _GroupCard(
                    group: group,
                    currentUserId: currentUserId,
                    chatTitle: _chatTitle,
                    chatRoleLabel: _chatRoleLabel,
                    onTap: (chat) async {
                      if (_isNavigating) return;
                      _isNavigating = true;
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ChatConversationScreen(chat: chat),
                        ),
                      );
                      if (mounted) setState(() => _isNavigating = false);
                    },
                  );
                }, childCount: groups.length),
              );
            },
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
      ),
    );
  }
}

// ─── Group Card ───────────────────────────────────────────────────────────────
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.currentUserId,
    required this.chatTitle,
    required this.chatRoleLabel,
    required this.onTap,
  });

  final _ChatGroup group;
  final String? currentUserId;
  final String Function(Chat, String?) chatTitle;
  final String Function(Chat) chatRoleLabel;
  final void Function(Chat) onTap;

  int get totalUnread => group.chats.fold(0, (s, c) => s + c.unreadCount);

  @override
  Widget build(BuildContext context) {
    final hasUnread = totalUnread > 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Group Header ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 8, left: 2),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: hasUnread
                          ? [primaryOrange, const Color(0xFFFF9800)]
                          : [const Color(0xFFE5E7EB), const Color(0xFFD1D5DB)],
                    ),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.receipt_long_rounded,
                        size: 12,
                        color: hasUnread ? Colors.white : textGray600,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        group.groupLabel,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: hasUnread ? Colors.white : textGray600,
                          letterSpacing: 0.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _relativeTime(group.lastActivity),
                  style: const TextStyle(
                    fontSize: 11,
                    color: textGray600,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                if (hasUnread) ...[
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: primaryOrange,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      totalUnread > 99 ? '99+' : '$totalUnread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Chat rows inside the group ───────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: backgroundWhite,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: hasUnread
                    ? primaryOrange.withValues(alpha: 0.25)
                    : borderGray100,
                width: hasUnread ? 1.5 : 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: hasUnread
                      ? primaryOrange.withValues(alpha: 0.08)
                      : Colors.black.withValues(alpha: 0.04),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Column(
              children: group.chats.asMap().entries.map((entry) {
                final i = entry.key;
                final chat = entry.value;
                final isLast = i == group.chats.length - 1;
                return _ChatRow(
                  chat: chat,
                  currentUserId: currentUserId,
                  participantName: chatTitle(chat, currentUserId),
                  roleLabel: chatRoleLabel(chat),
                  isLast: isLast,
                  onTap: () => onTap(chat),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Chat Row ─────────────────────────────────────────────────────────────────
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.chat,
    required this.currentUserId,
    required this.participantName,
    required this.roleLabel,
    required this.isLast,
    required this.onTap,
  });

  final Chat chat;
  final String? currentUserId;
  final String participantName;
  final String roleLabel;
  final bool isLast;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasUnread = chat.unreadCount > 0;
    final lastMsg = chat.lastMessageText.isEmpty
        ? 'Sin mensajes'
        : chat.lastMessageText;
    final isFromMe = chat.lastMessageSenderId == currentUserId;
    final initials = _initials(participantName);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              Stack(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: hasUnread
                            ? [primaryOrange, const Color(0xFFFF9800)]
                            : [
                                primaryOrange.withValues(alpha: 0.15),
                                primaryOrange.withValues(alpha: 0.08),
                              ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      initials,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        color: hasUnread ? Colors.white : primaryOrange,
                      ),
                    ),
                  ),
                  if (hasUnread)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(color: Color(0x4010B981), blurRadius: 4),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          chat.unreadCount > 9 ? '9+' : '${chat.unreadCount}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 12),

              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            participantName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: textGray900,
                              fontWeight: hasUnread
                                  ? FontWeight.w800
                                  : FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        // Chat type pill
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: primaryOrange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            roleLabel,
                            style: const TextStyle(
                              color: primaryOrange,
                              fontSize: 9,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (isFromMe)
                          const Padding(
                            padding: EdgeInsets.only(right: 3),
                            child: Icon(
                              Icons.done_all,
                              size: 13,
                              color: primaryOrange,
                            ),
                          ),
                        Expanded(
                          child: Text(
                            lastMsg,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: hasUnread ? textGray900 : textGray600,
                              fontWeight: hasUnread
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right_rounded,
                color: textGray600,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── Empty State ──────────────────────────────────────────────────────────────
class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 90,
              height: 90,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    primaryOrange.withValues(alpha: 0.15),
                    primaryOrange.withValues(alpha: 0.05),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: primaryOrange,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Sin conversaciones aún',
              style: TextStyle(
                color: textGray900,
                fontSize: 18,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tus conversaciones con riders y vendedores aparecerán aquí',
              style: TextStyle(color: textGray600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Error State ──────────────────────────────────────────────────────────────
class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 52,
              color: textGray600.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Text(
              message,
              style: const TextStyle(color: textGray600, fontSize: 14),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
