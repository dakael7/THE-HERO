import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../data/providers/network_providers.dart';
import '../../../../data/providers/repository_providers.dart';
import '../../../../domain/entities/chat.dart';
import '../../../../domain/entities/chat_type.dart';
import '../../../../domain/entities/offer.dart';
import '../../../../features/orders/presentation/providers/orders_provider.dart';
import '../../../../features/shared/chat/presentation/providers/chat_providers.dart';
import '../../../../features/shared/chat/presentation/views/chat_conversation_screen.dart';
import '../../../../features/shared/profile/presentation/providers/profile_provider.dart';

final _offerByIdProvider = FutureProvider.autoDispose.family<Offer?, String>((
  ref,
  offerId,
) async {
  final repo = ref.read(offersRepositoryProvider);
  return repo.getOfferById(offerId);
});

class RiderDeliveryChatsScreen extends ConsumerWidget {
  final String orderId;

  const RiderDeliveryChatsScreen({super.key, required this.orderId});

  Future<void> _callPhone(BuildContext context, String phone) async {
    final trimmed = phone.trim();
    if (trimmed.isEmpty) return;
    final uri = Uri.parse('tel:$trimmed');
    final ok = await launchUrl(uri);
    if (!ok && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir la llamada')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orderAsync = ref.watch(orderByIdProvider(orderId));
    final riderId = ref.watch(profileProvider).value?.id;

    return Scaffold(
      backgroundColor: backgroundGray50,
      appBar: AppBar(
        backgroundColor: primaryYellow,
        foregroundColor: textGray900,
        elevation: 0,
        title: const Text(
          'Chats',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: orderAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: primaryOrange),
        ),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (order) {
          if (order == null) {
            return const Center(child: Text('Pedido no disponible'));
          }

          if (riderId == null || riderId.trim().isEmpty) {
            return const Center(
              child: Text('Inicia sesión para ver los chats'),
            );
          }

          if (!order.status.canShowAssociatedChats) {
            return const Center(
              child: Text(
                'Los chats estarán disponibles cuando el pedido esté pagado',
              ),
            );
          }

          final stops = order.pickupStops ?? const [];
          final offerIds = <String>{
            for (final s in stops)
              ...s.offerIds.where((id) => id.trim().isNotEmpty),
          }.toList();

          final buyerAsync = ref.watch(userByIdProvider(order.heroId));
          final buyerPhone = buyerAsync.maybeWhen(
            data: (u) => u?.phoneNumber,
            orElse: () => null,
          );
          final clientPhone =
              (buyerPhone != null && buyerPhone.trim().isNotEmpty)
              ? buyerPhone
              : (order.delivery.recipientPhone.trim().isNotEmpty
                    ? order.delivery.recipientPhone
                    : null);

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _ChatTargetTile(
                roleLabel: 'Cliente',
                name: order.delivery.recipientName.isNotEmpty
                    ? order.delivery.recipientName
                    : 'Hero',
                phoneNumber: clientPhone,
                onCall: clientPhone == null
                    ? null
                    : () => _callPhone(context, clientPhone),
                onOpen: () async {
                  final now = DateTime.now();
                  final newChatId = Chat.generateChatId(
                    type: ChatType.heroRider,
                    buyerId: order.heroId,
                    riderId: riderId,
                    orderId: order.orderId,
                  );
                  final legacyChatId =
                      '${ChatType.heroRider.jsonValue}_order_${order.orderId}';

                  final docNew = await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(newChatId)
                      .get();
                  final docLegacy = docNew.exists
                      ? null
                      : await FirebaseFirestore.instance
                            .collection('chats')
                            .doc(legacyChatId)
                            .get();

                  final legacyOk = (() {
                    if (!(docLegacy?.exists ?? false)) return false;
                    final data = docLegacy!.data() ?? <String, dynamic>{};
                    final legacyBuyerId =
                        (data['buyerId'] as String?) ??
                        (data['heroId'] as String?) ??
                        '';
                    final legacyRiderId = (data['riderId'] as String?) ?? '';
                    final rawParticipantIds = data['participantIds'];
                    final participantIds = rawParticipantIds is List
                        ? rawParticipantIds
                              .map((e) => e.toString().trim())
                              .where((e) => e.isNotEmpty)
                              .toList()
                        : <String>[];
                    final expected = <String>[
                      order.heroId.trim(),
                      riderId.trim(),
                    ];
                    final hasOnlyExpected =
                        participantIds.length == 2 &&
                        participantIds.toSet().containsAll(expected) &&
                        expected.toSet().containsAll(participantIds.toSet());

                    final legacySellerId = (data['sellerId'] as String?) ?? '';
                    return legacyBuyerId.trim() == order.heroId.trim() &&
                        legacyRiderId.trim() == riderId.trim() &&
                        legacySellerId.trim().isEmpty &&
                        hasOnlyExpected;
                  })();

                  final chatId = docNew.exists
                      ? newChatId
                      : (legacyOk ? legacyChatId : newChatId);

                  final chat = Chat(
                    chatId: chatId,
                    type: ChatType.heroRider,
                    orderId: order.orderId,
                    buyerId: order.heroId,
                    buyerName: order.delivery.recipientName.isNotEmpty
                        ? order.delivery.recipientName
                        : 'Hero',
                    riderId: riderId,
                    riderName: ref.read(profileProvider).value?.fullName,
                    createdAt: now,
                    updatedAt: now,
                    lastMessageText: '',
                    lastMessageAt: now,
                    lastMessageSenderId: null,
                    unreadCount: 0,
                  );

                  if (!context.mounted) return;
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ChatConversationScreen(chat: chat),
                    ),
                  );

                  Future.microtask(() async {
                    try {
                      await ref
                          .read(chatActionsProvider)
                          .ensureChatExists(chat);
                    } catch (_) {
                      // Silently ignore
                    }
                  });
                },
                chatId: Chat.generateChatId(
                  type: ChatType.heroRider,
                  buyerId: order.heroId,
                  riderId: riderId,
                  orderId: order.orderId,
                ),
              ),
              const SizedBox(height: 12),
              const Text(
                'Donadores',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textGray900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              if (offerIds.isEmpty)
                const _EmptyInfo(
                  icon: Icons.volunteer_activism_outlined,
                  title: 'Sin donadores',
                  message: 'Este pedido no tiene paradas de recogida.',
                )
              else
                ...offerIds.map(
                  (offerId) => _DonorTile(
                    orderId: order.orderId,
                    riderId: riderId,
                    offerId: offerId,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DonorTile extends ConsumerWidget {
  final String orderId;
  final String riderId;
  final String offerId;

  const _DonorTile({
    required this.orderId,
    required this.riderId,
    required this.offerId,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offerAsync = ref.watch(_offerByIdProvider(offerId));

    return offerAsync.when(
      loading: () => const _SkeletonTile(),
      error: (e, _) => _ChatTargetTile(
        roleLabel: 'Donador',
        name: 'No disponible',
        chatId: null,
        onOpen: null,
        trailing: const Icon(Icons.error_outline, color: textGray600),
      ),
      data: (offer) {
        final donorId = offer?.heroId ?? '';
        if (donorId.trim().isEmpty) {
          return _ChatTargetTile(
            roleLabel: 'Donador',
            name: offer?.title ?? 'Donador',
            chatId: null,
            onOpen: null,
          );
        }

        final donorAsync = ref.watch(userByIdProvider(donorId));
        final donorName = donorAsync.maybeWhen(
          data: (u) =>
              u?.fullName.trim().isNotEmpty == true ? u!.fullName : 'Donador',
          orElse: () => 'Donador',
        );

        final donorPhone = donorAsync.maybeWhen(
          data: (u) => u?.phoneNumber,
          orElse: () => null,
        );

        final uniqueDonorChatId =
            '${ChatType.heroRider.jsonValue}_${donorId}_${riderId}_order_$orderId';

        return _ChatTargetTile(
          roleLabel: 'Donador',
          name: donorName,
          subtitle: offer?.title,
          chatId: uniqueDonorChatId,
          phoneNumber: donorPhone,
          onCall: (donorPhone == null || donorPhone.trim().isEmpty)
              ? null
              : () async {
                  final uri = Uri.parse('tel:${donorPhone.trim()}');
                  final ok = await launchUrl(uri);
                  if (!ok && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('No se pudo abrir la llamada'),
                      ),
                    );
                  }
                },
          onOpen: () async {
            final now = DateTime.now();
            final chat = Chat(
              chatId: uniqueDonorChatId,
              type: ChatType.heroRider,
              orderId: orderId,
              buyerId: donorId,
              buyerName: donorName,
              riderId: riderId,
              riderName: ref.read(profileProvider).value?.fullName,
              createdAt: now,
              updatedAt: now,
              lastMessageText: '',
              lastMessageAt: now,
              lastMessageSenderId: null,
              unreadCount: 0,
            );

            if (!context.mounted) return;
            // Navigate immediately, ensure chat in background
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => ChatConversationScreen(chat: chat),
              ),
            );

            // Ensure chat exists in background without blocking
            Future.microtask(() async {
              try {
                await ref.read(chatActionsProvider).ensureChatExists(chat);
              } catch (_) {
                // Silently ignore
              }
            });
          },
        );
      },
    );
  }
}

class _ChatTargetTile extends ConsumerStatefulWidget {
  final String roleLabel;
  final String name;
  final String? subtitle;
  final String? chatId;
  final Future<void> Function()? onOpen;
  final String? phoneNumber;
  final VoidCallback? onCall;
  final Widget? trailing;

  const _ChatTargetTile({
    required this.roleLabel,
    required this.name,
    required this.chatId,
    required this.onOpen,
    this.subtitle,
    this.phoneNumber,
    this.onCall,
    this.trailing,
  });

  @override
  ConsumerState<_ChatTargetTile> createState() => _ChatTargetTileState();
}

class _ChatTargetTileState extends ConsumerState<_ChatTargetTile> {
  bool _isNavigating = false;

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

  String _formatTime(DateTime? dt) {
    if (dt == null) return '';
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context) {
    final currentUid = ref.watch(firebaseAuthProvider).currentUser?.uid;
    final id = widget.chatId;
    final chatAsync = (id == null || id.trim().isEmpty)
        ? const AsyncValue.data(null)
        : ref.watch(chatByIdProvider(id));

    final badgeCount = chatAsync.maybeWhen(
      data: (chat) {
        if (chat == null) return 0;
        if (currentUid == null) return 0;
        if (chat.unreadCount <= 0) return 0;
        if ((chat.lastMessageSenderId ?? '').trim() == currentUid) return 0;
        return chat.unreadCount;
      },
      orElse: () => 0,
    );

    final lastPreview = chatAsync.maybeWhen(
      data: (chat) {
        final text = (chat?.lastMessageText ?? '').trim();
        if (text.isEmpty) return 'Sin mensajes';
        return text;
      },
      orElse: () => 'Sin mensajes',
    );

    final lastTime = chatAsync.maybeWhen(
      data: (chat) => _formatTime(chat?.lastMessageAt),
      orElse: () => '',
    );

    final effectiveSubtitle =
        (widget.subtitle != null && widget.subtitle!.trim().isNotEmpty)
        ? widget.subtitle!.trim()
        : null;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ListTile(
        onTap: widget.onOpen != null
            ? () async {
                if (_isNavigating) return;
                _isNavigating = true;

                await widget.onOpen!();

                if (mounted) {
                  setState(() => _isNavigating = false);
                }
              }
            : null,
        enabled: widget.onOpen != null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: primaryOrange.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderGray100),
          ),
          alignment: Alignment.center,
          child: Text(
            _initials(widget.name),
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: primaryOrange,
            ),
          ),
        ),
        title: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: textGray900,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: backgroundGray50,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: borderGray100),
                    ),
                    child: Text(
                      widget.roleLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: textGray600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (lastTime.isNotEmpty) ...[
              const SizedBox(width: 10),
              Text(
                lastTime,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: textGray600,
                ),
              ),
            ],
          ],
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 4),
            if (effectiveSubtitle != null)
              Text(
                effectiveSubtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textGray900,
                  fontSize: 12,
                ),
              ),
            Text(
              lastPreview,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                color: textGray600,
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing:
            widget.trailing ??
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.onCall != null) ...[
                  InkWell(
                    onTap: widget.onCall,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: backgroundGray50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: borderGray100),
                      ),
                      alignment: Alignment.center,
                      child: const Icon(
                        Icons.call,
                        size: 18,
                        color: primaryOrange,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                _BadgeOrChevron(count: badgeCount),
              ],
            ),
      ),
    );
  }
}

class _BadgeOrChevron extends StatelessWidget {
  final int count;

  const _BadgeOrChevron({required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) {
      return const Icon(Icons.chevron_right, color: textGray600);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: primaryOrange,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        count > 99 ? '99+' : count.toString(),
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w900,
          color: Colors.white,
        ),
      ),
    );
  }
}

class _EmptyInfo extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;

  const _EmptyInfo({
    required this.icon,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primaryOrange.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: primaryOrange),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textGray900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  message,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: textGray600,
                    fontSize: 12,
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

class _SkeletonTile extends StatelessWidget {
  const _SkeletonTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderGray100),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: borderGray100,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: 160,
                  decoration: BoxDecoration(
                    color: borderGray100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  height: 10,
                  width: 100,
                  decoration: BoxDecoration(
                    color: borderGray100,
                    borderRadius: BorderRadius.circular(6),
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
