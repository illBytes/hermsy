import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/chat_message.dart';
import '../presence/presence_engine.dart';
import '../services/delivery_inbox.dart';
import '../services/relay_client.dart' show relayPlainText;
import '../services/relay_sync.dart';
import '../theme/app_theme.dart';
import '../widgets/day_separator.dart' show dayLabel;
import '../widgets/frank_backdrop.dart';
import '../widgets/frank_orb.dart';
import '../widgets/message_image.dart';
import '../widgets/report_reply.dart';
import '../widgets/ui/frank_ui.dart';
import 'message_reader_screen.dart';

/// Opens a delivery in the full-screen reader, titled with its title. With
/// [onReply], a Reply button returns to the chat and calls it.
Future<void> showDeliveryReader(
  BuildContext context,
  DeliveryRecord record, {
  ValueChanged<DeliveryRecord>? onReply,
}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (context) => MessageReaderScreen(
        title: record.title,
        onReply: onReply == null
            ? null
            : () {
                Navigator.of(context).popUntil((route) => route.isFirst);
                onReply(record);
              },
        message: ChatMessage(
          id: record.id,
          role: MessageRole.assistant,
          text: record.body,
          createdAt: record.createdAt,
        ),
      ),
    ),
  );
}

class InboxScreen extends StatefulWidget {
  const InboxScreen({super.key, this.inbox, this.onReply});

  final DeliveryInbox? inbox;

  /// Replies to a message Hermes sent on its own, in its own chat thread.
  final ValueChanged<DeliveryRecord>? onReply;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  /// Null until the first read finishes, so an inbox with items never
  /// flashes its empty state.
  List<DeliveryRecord>? _items;
  DeliveryInbox? _inbox;

  /// What was unread when you came in: marked with a dot for this visit,
  /// though opening the Inbox has already counted it as seen.
  Set<String> _fresh = const {};

  /// The Undo bar after a delete. It belongs to the inbox, so it goes when
  /// you leave.
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _undoBar;

  @override
  void dispose() {
    _undoBar?.close();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _load(arriving: true);
  }

  Future<DeliveryInbox> _open() async =>
      _inbox ??= widget.inbox ?? await DeliveryInbox.open();

  Future<void> _load({bool arriving = false}) async {
    List<DeliveryRecord> items;
    try {
      final inbox = await _open();
      items = await inbox.list();
      if (arriving) {
        _fresh = {
          for (final item in items)
            if (!item.read) item.id,
        };
        await inbox.markAllRead();
      }
    } catch (_) {
      items = const [];
    }
    if (!mounted) {
      return;
    }
    setState(() => _items = items);
  }

  /// Gone from the list at once; Undo puts it back.
  Future<void> _delete(DeliveryRecord record) async {
    setState(() => _items = [...?_items]..remove(record));
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      await (await _open()).remove(record.id);
    } catch (_) {
      await _load();
      return;
    }
    messenger?.hideCurrentSnackBar();
    final bar = _undoBar = messenger?.showSnackBar(
      SnackBar(
        content: const Text('Message deleted'),
        // A bar with an action would otherwise stay until dismissed.
        persist: false,
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await (await _open()).add(record);
            await _load();
          },
        ),
      ),
    );
    // Once it is gone there is nothing to close when you leave.
    bar?.closed.whenComplete(() {
      if (identical(_undoBar, bar)) {
        _undoBar = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: InboxBody(
          items: _items ?? const [],
          loading: _items == null,
          header: const LargeTitleSliverBar(title: 'Inbox'),
          onReply: widget.onReply,
          onDelete: _delete,
          fresh: _fresh,
        ),
      ),
    );
  }
}

/// The inbox list: deliveries grouped by day, newest first, or the empty
/// state. [header] is an optional sliver placed above (the large title).
class InboxBody extends StatelessWidget {
  const InboxBody({
    super.key,
    required this.items,
    this.loading = false,
    this.header,
    this.now,
    this.onReply,
    this.onDelete,
    this.fresh = const {},
  });

  final List<DeliveryRecord> items;

  /// Ids of deliveries new since you last looked: they get a dot.
  final Set<String> fresh;

  /// See [InboxScreen.onReply].
  final ValueChanged<DeliveryRecord>? onReply;

  /// Deletes a delivery: swipe it away, or long-press and choose Delete.
  final ValueChanged<DeliveryRecord>? onDelete;

  /// Shows nothing below the header while the inbox is read.
  final bool loading;
  final Widget? header;

  /// Overrides the clock for day labels (tests).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final side = math.max(AppSpace.gutter, (media.size.width - 640) / 2);
    final top = header == null ? media.padding.top + AppSpace.x2 : AppSpace.x1;
    return CustomScrollView(
      slivers: [
        ?header,
        if (loading)
          const SliverToBoxAdapter(child: SizedBox.shrink())
        else if (items.isEmpty)
          SliverPadding(
            padding: EdgeInsets.only(top: top, bottom: media.padding.bottom),
            sliver: const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyInbox(),
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.fromLTRB(
              side + media.padding.left,
              top,
              side + media.padding.right,
              AppSpace.x10 + media.padding.bottom,
            ),
            sliver: _DeliveryList(
              items: items,
              now: now ?? DateTime.now(),
              onReply: onReply,
              onDelete: onDelete,
              fresh: fresh,
            ),
          ),
      ],
    );
  }
}

/// One row of the inbox list: a day label or a delivery.
typedef _InboxRow = ({String? day, DeliveryRecord? item});

class _DeliveryList extends StatelessWidget {
  const _DeliveryList({
    required this.items,
    required this.now,
    this.onReply,
    this.onDelete,
    this.fresh = const {},
  });

  final List<DeliveryRecord> items;
  final Set<String> fresh;
  final DateTime now;
  final ValueChanged<DeliveryRecord>? onReply;
  final ValueChanged<DeliveryRecord>? onDelete;

  List<_InboxRow> _rows() {
    final rows = <_InboxRow>[];
    String? day;
    for (final item in items) {
      final label = dayLabel(item.createdAt, now: now);
      if (label != day) {
        day = label;
        rows.add((day: label, item: null));
      }
      rows.add((day: null, item: item));
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final rows = _rows();
    return SliverList.builder(
      itemCount: rows.length,
      itemBuilder: (context, index) {
        final row = rows[index];
        final day = row.day;
        if (day != null) {
          return _DayLabel(day, first: index == 0);
        }
        final next = index + 1 < rows.length ? rows[index + 1] : null;
        final item = row.item!;
        Widget card = _DeliveryCard(
          item: item,
          onReply: onReply,
          onDelete: onDelete,
          fresh: fresh.contains(item.id),
        );
        final delete = onDelete;
        if (delete != null) {
          card = Dismissible(
            key: ValueKey(item.id),
            direction: DismissDirection.endToStart,
            background: const _DeleteBehind(),
            onDismissed: (_) => delete(item),
            child: card,
          );
        }
        return Padding(
          padding: EdgeInsets.only(
            bottom: next == null || next.day != null ? 0 : AppSpace.x3,
          ),
          child: card,
        );
      },
    );
  }
}

/// What a card uncovers as it is swiped away.
class _DeleteBehind extends StatelessWidget {
  const _DeleteBehind();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.signal.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadii.lg),
      ),
      child: Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 24),
          child: Icon(Icons.delete_outline_rounded, color: AppColors.danger),
        ),
      ),
    );
  }
}

/// A day heading: a micro label trailed by a hairline.
class _DayLabel extends StatelessWidget {
  const _DayLabel(this.label, {required this.first});

  final String label;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(4, first ? 4 : 28, 0, 12),
      child: Semantics(
        header: true,
        child: Row(
          children: [
            MicroLabel(label, padding: EdgeInsets.zero),
            const SizedBox(width: AppSpace.x3),
            Expanded(
              child: Divider(
                height: 1,
                thickness: 1,
                color: AppColors.hairline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyInbox extends StatelessWidget {
  const _EmptyInbox();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.3),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(32, 24, 32, 48),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const FrankOrb(size: 64, live: false, lit: false),
              const SizedBox(height: AppSpace.x6),
              Text(
                'Nothing here yet',
                textAlign: TextAlign.center,
                style: AppText.title,
              ),
              const SizedBox(height: AppSpace.x3),
              Text(
                'Messages Hermsy sends on its own, like scheduled job '
                'results, land here. So do pictures and files from a chat.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.secondary,
                  fontSize: 15,
                  height: 1.47,
                ),
              ),
              const SizedBox(height: AppSpace.x3),
              Text(
                'A job reaches this phone when Hermes delivers it to frank.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.hint,
                  fontSize: 13.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({
    required this.item,
    this.onReply,
    this.onDelete,
    this.fresh = false,
  });

  final DeliveryRecord item;

  /// New since you last looked.
  final bool fresh;
  final ValueChanged<DeliveryRecord>? onReply;
  final ValueChanged<DeliveryRecord>? onDelete;

  /// The title is usually the body's first line; show that line once.
  ({String title, String body}) _text() {
    // Hermes writes Markdown; the card is a preview, so it reads as plain
    // text. The reader shows it formatted.
    final body = isRelayRecord(item)
        ? relayPlainText(item.body)
        : item.body.trim();
    final lines = body.split(RegExp(r'\n+'));
    final first = lines.first.trim();
    final title = item.title;
    final stem = title.endsWith('…')
        ? title.substring(0, title.length - 1)
        : title;
    final repeats =
        first.isNotEmpty &&
        (first == title || (title.endsWith('…') && first.startsWith(stem)));
    if (!repeats) {
      return (title: title, body: body);
    }
    return (title: first, body: lines.skip(1).join('\n').trim());
  }

  String _clock(BuildContext context) {
    if (item.createdAt.millisecondsSinceEpoch <= 0) {
      return '';
    }
    return MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(item.createdAt.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
  }

  void _copy(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    if (PresenceScope.maybeOf(context)?.settings?.haptics ?? true) {
      HapticFeedback.selectionClick();
    }
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Copied')));
  }

  /// Long-press: copy it, or delete it.
  Future<void> _actions(BuildContext context, String title, String text) {
    if (PresenceScope.maybeOf(context)?.settings?.haptics ?? true) {
      HapticFeedback.selectionClick();
    }
    final delete = onDelete;
    return showFrankSheet<void>(
      context,
      builder: (sheetContext) => FrankSheet(
        title: title,
        children: [
          SheetRow(
            icon: Icons.copy_rounded,
            label: 'Copy',
            onTap: () {
              Navigator.of(sheetContext).pop();
              _copy(context, text);
            },
          ),
          // What Hermes wrote on its own can be reported, like a reply.
          if (isRelayRecord(item))
            SheetRow(
              icon: Icons.outlined_flag_rounded,
              label: 'Report',
              onTap: () {
                Navigator.of(sheetContext).pop();
                reportReply(
                  context,
                  reply: item.body,
                  sentAt: item.createdAt,
                  source: 'message Hermsy sent on its own',
                );
              },
            ),
          if (delete != null) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.x1),
              child: Divider(indent: 56, endIndent: 6),
            ),
            SheetRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              danger: true,
              onTap: () {
                Navigator.of(sheetContext).pop();
                delete(item);
              },
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final (:title, :body) = _text();
    final clock = _clock(context);
    final hasImages = item.filePaths.isNotEmpty || item.remotePaths.isNotEmpty;
    final copyText = body.isNotEmpty ? '$title\n$body' : title;
    return Material(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.lg),
        side: BorderSide(color: AppColors.veil(0x0D)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Messages from Hermes open in full; chat files show here as they are.
        onTap: isRelayRecord(item)
            ? () => showDeliveryReader(context, item, onReply: onReply)
            : null,
        onLongPress: () => _actions(context, title, copyText),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (fresh)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, right: 8),
                      child: Semantics(
                        label: 'New',
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.gold,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(fontSize: 16, height: 1.35),
                    ),
                  ),
                  if (clock.isNotEmpty) ...[
                    const SizedBox(width: AppSpace.x3),
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        clock,
                        style: AppText.tabular.copyWith(color: AppColors.hint),
                      ),
                    ),
                  ],
                ],
              ),
              if (body.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: AppText.bodySmall,
                ),
              ],
              if (hasImages) ...[
                const SizedBox(height: AppSpace.x3),
                // A light edge keeps pictures (and name-only placeholders,
                // which share the card's black) reading as tiles.
                Container(
                  foregroundDecoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.md),
                    border: Border.all(color: AppColors.hairline),
                  ),
                  child: MessageImageStrip(
                    paths: item.filePaths,
                    remotes: item.remotePaths,
                    radius: AppRadii.md,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
