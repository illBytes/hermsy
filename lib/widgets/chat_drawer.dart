import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/conversation_store.dart';
import '../services/delivery_inbox.dart';
import '../state/assistant_mood.dart';
import '../state/chat_controller.dart';
import '../theme/app_theme.dart';
import 'chat_error_strip.dart' show isVoiceError;
import 'chat_header.dart' show ChatStatus, chatStatusFor;
import 'confirm_delete_chat.dart';
import 'frank_mark.dart';
import 'prompt_rename_chat.dart';
import 'ui/frank_ui.dart';

/// The chat history drawer: Frank's status, a New chat pill, search, and
/// date-bucketed conversations. Swipe a chat left to delete it; hold it to
/// rename, pin, or delete. Its footer reaches the Inbox (with what is
/// unread), Settings, and the lock in one tap each.
class ChatDrawer extends StatefulWidget {
  const ChatDrawer({
    super.key,
    required this.controller,
    required this.onOpenSettings,
    this.onOpenInbox,
    this.onLock,
  });

  final ChatController controller;
  final VoidCallback onOpenSettings;
  final VoidCallback? onOpenInbox;
  final VoidCallback? onLock;

  @override
  State<ChatDrawer> createState() => _ChatDrawerState();
}

/// A titled run of conversations in the drawer ("Pinned", "Today", …).
class ConversationSection {
  const ConversationSection(
    this.label,
    this.items, {
    this.clockForYesterday = false,
  });

  final String label;
  final List<ConversationSummary> items;

  /// Rows in this section show the clock even for yesterday's chats, because
  /// the section label already says the day.
  final bool clockForYesterday;
}

/// Splits [items] into Pinned, Today, Yesterday, Previous 7 days and Older by
/// [ConversationSummary.updatedAt], keeping their order. Empty sections are
/// left out.
List<ConversationSection> groupConversations(
  List<ConversationSummary> items, {
  DateTime? now,
}) {
  final clock = (now ?? DateTime.now()).toLocal();
  final today = DateTime(clock.year, clock.month, clock.day);
  final yesterday = DateTime(clock.year, clock.month, clock.day - 1);
  final weekStart = DateTime(clock.year, clock.month, clock.day - 7);

  final pinned = <ConversationSummary>[];
  final todays = <ConversationSummary>[];
  final yesterdays = <ConversationSummary>[];
  final week = <ConversationSummary>[];
  final older = <ConversationSummary>[];

  for (final item in items) {
    if (item.pinned) {
      pinned.add(item);
      continue;
    }
    if (item.updatedAt.millisecondsSinceEpoch <= 0) {
      older.add(item);
      continue;
    }
    final local = item.updatedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (!day.isBefore(today)) {
      todays.add(item);
    } else if (day == yesterday) {
      yesterdays.add(item);
    } else if (!day.isBefore(weekStart)) {
      week.add(item);
    } else {
      older.add(item);
    }
  }

  return [
    if (pinned.isNotEmpty) ConversationSection('Pinned', pinned),
    if (todays.isNotEmpty) ConversationSection('Today', todays),
    if (yesterdays.isNotEmpty)
      ConversationSection('Yesterday', yesterdays, clockForYesterday: true),
    if (week.isNotEmpty) ConversationSection('Previous 7 days', week),
    if (older.isNotEmpty) ConversationSection('Older', older),
  ];
}

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// The short time on a drawer row: the clock today, "Yesterday", the weekday
/// within a week, "Sep 3" this year, then "Sep 3, 2024". Empty for unknown
/// times.
String drawerTimeLabel(
  DateTime time, {
  DateTime? now,
  bool use24h = true,
  bool clockForYesterday = false,
}) {
  if (time.millisecondsSinceEpoch <= 0) {
    return '';
  }
  final local = time.toLocal();
  final clock = (now ?? DateTime.now()).toLocal();
  final day = DateTime(local.year, local.month, local.day);
  final today = DateTime(clock.year, clock.month, clock.day);
  if (!day.isBefore(today)) {
    return _clockLabel(local, use24h);
  }
  if (day == DateTime(clock.year, clock.month, clock.day - 1)) {
    return clockForYesterday ? _clockLabel(local, use24h) : 'Yesterday';
  }
  if (!day.isBefore(DateTime(clock.year, clock.month, clock.day - 6))) {
    return _weekdays[local.weekday - 1];
  }
  final date = '${_months[local.month - 1]} ${local.day}';
  return local.year == clock.year ? date : '$date, ${local.year}';
}

String _clockLabel(DateTime time, bool use24h) {
  final minutes = time.minute.toString().padLeft(2, '0');
  if (use24h) {
    return '${time.hour.toString().padLeft(2, '0')}:$minutes';
  }
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  return '$hour:$minutes ${time.hour < 12 ? 'AM' : 'PM'}';
}

/// "Today · 14:32", "Yesterday · 9:05 AM", "Sep 3 · 14:32", "Sep 3, 2024".
String _detailedWhen(DateTime time, {required bool use24h}) {
  if (time.millisecondsSinceEpoch <= 0) {
    return '';
  }
  final local = time.toLocal();
  final now = DateTime.now();
  final clock = _clockLabel(local, use24h);
  final day = DateTime(local.year, local.month, local.day);
  if (day == DateTime(now.year, now.month, now.day)) {
    return 'Today · $clock';
  }
  if (day == DateTime(now.year, now.month, now.day - 1)) {
    return 'Yesterday · $clock';
  }
  final date = '${_months[local.month - 1]} ${local.day}';
  return local.year == now.year ? '$date · $clock' : '$date, ${local.year}';
}

/// Rows at the top of the list that join the staggered entrance.
const _staggerRows = 8;
const _staggerStep = Duration(milliseconds: 30);
const _rowEnter = Duration(milliseconds: 260);

class _ChatDrawerState extends State<ChatDrawer>
    with SingleTickerProviderStateMixin {
  final _dismissed = <String>{};
  final _search = TextEditingController();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: _staggerStep * (_staggerRows - 1) + _rowEnter,
  );
  late _DrawerSnapshot _snap;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    final chat = widget.controller;
    unawaited(chat.refreshHistory());
    _snap = _DrawerSnapshot.of(chat);
    chat.addListener(_onChat);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        AppMotion.reduced(context) ||
        (widget.controller.settings?.reduceMotion ?? false);
    _maybeEnter();
  }

  @override
  void didUpdateWidget(covariant ChatDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onChat);
      widget.controller.addListener(_onChat);
      _snap = _DrawerSnapshot.of(widget.controller);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChat);
    _entrance.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Rebuild only when something the drawer shows changed, not on every
  /// streamed token.
  void _onChat() {
    final next = _DrawerSnapshot.of(widget.controller);
    if (next.sameAs(_snap)) {
      return;
    }
    setState(() => _snap = next);
    _maybeEnter();
  }

  /// Plays the row entrance once, as soon as there are rows to show.
  void _maybeEnter() {
    if (!_entrance.isDismissed || !_snap.history.any(_listed)) {
      return;
    }
    if (_reduceMotion) {
      _entrance.value = 1;
    } else {
      _entrance.forward();
    }
  }

  bool _listed(ConversationSummary item) {
    return !item.isRemoteOnly && !_dismissed.contains(item.id);
  }

  void _close() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold != null) {
      scaffold.closeDrawer();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = widget.controller;
    final snap = _snap;
    final width = math.min(MediaQuery.sizeOf(context).width * 0.86, 360.0);

    return Drawer(
      width: width,
      backgroundColor: AppColors.glow.withValues(alpha: 0.98),
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      semanticLabel: 'Chats',
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.horizontal(
          right: Radius.circular(AppRadii.sheet),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: CustomPaint(
        foregroundPainter: const _EdgeLightPainter(radius: AppRadii.sheet),
        child: SafeArea(
          right: false,
          child: _KeyboardInset(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DrawerHeader(
                  status: _statusOf(snap),
                  mood: snap.mood,
                  lit: snap.connected || snap.loading,
                  // The mic level drives the orb only while Frank listens;
                  // otherwise it runs its own speech swell and token pump.
                  level: snap.mood == AssistantMood.listening
                      ? chat.voiceLevel
                      : null,
                  reduceMotion: _reduceMotion,
                ),
                const SizedBox(height: AppSpace.x5),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
                  child: _NewChatPill(
                    onTap: snap.sending
                        ? null
                        : () {
                            chat.haptics?.tap();
                            chat.newChat();
                            _close();
                          },
                  ),
                ),
                const SizedBox(height: AppSpace.x3),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpace.x3),
                  child: _SearchField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: AppSpace.x1),
                Expanded(child: _body(chat, snap)),
                _HiddenWithKeyboard(
                  child: _DrawerFooter(
                    onInbox: widget.onOpenInbox == null
                        ? null
                        : () {
                            chat.haptics?.tap();
                            widget.onOpenInbox!();
                          },
                    onSettings: () {
                      chat.haptics?.tap();
                      widget.onOpenSettings();
                    },
                    onLock: widget.onLock,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(ChatController chat, _DrawerSnapshot snap) {
    if (snap.historyLoading && snap.history.isEmpty) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.6,
            color: AppColors.hint,
          ),
        ),
      );
    }

    final listed = snap.history.where(_listed).toList();
    final query = _search.text.trim();
    final visible = filterConversations(listed, query);
    if (visible.isEmpty) {
      return _EmptyHistory(searching: query.isNotEmpty);
    }

    final use24h = MediaQuery.alwaysUse24HourFormatOf(context);
    final now = DateTime.now();
    final live = moodIsBusy(snap.mood);
    final entries = <_Entry>[
      for (final section in groupConversations(visible, now: now)) ...[
        _LabelEntry(section.label),
        for (final item in section.items)
          _ChatEntry(
            item,
            drawerTimeLabel(
              item.updatedAt,
              now: now,
              use24h: use24h,
              clockForYesterday: section.clockForYesterday,
            ),
          ),
      ],
      if (query.isEmpty && listed.length < 3) const _HintEntry(),
    ];
    final indexByKey = {
      for (var i = 0; i < entries.length; i++) entries[i].key: i,
    };

    final list = ListView.builder(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x3,
        AppSpace.x1,
        AppSpace.x3,
        AppSpace.x4,
      ),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      itemCount: entries.length,
      findChildIndexCallback: (key) => indexByKey[key],
      itemBuilder: (context, index) {
        final entry = entries[index];
        final child = switch (entry) {
          _LabelEntry(:final label) => MicroLabel(
            label,
            padding: EdgeInsets.fromLTRB(
              AppSpace.x3,
              index == 0 ? AppSpace.x3 : AppSpace.x5,
              AppSpace.x3,
              AppSpace.x2,
            ),
          ),
          _ChatEntry(:final item, :final time) => _row(
            chat,
            item,
            time,
            current: item.id == snap.conversationId,
            live: live,
          ),
          _HintEntry() => const MicroLabel(
            'Hold a chat to rename, pin, or delete',
            padding: EdgeInsets.fromLTRB(
              AppSpace.x3,
              AppSpace.x5,
              AppSpace.x3,
              0,
            ),
          ),
        };
        // Everything past the first few steps enters with the last step, so
        // a tall screen never shows later rows before earlier ones.
        return _Stagger(
          key: entry.key,
          animation: _entrance,
          step: math.min(index, _staggerRows - 1),
          child: child,
        );
      },
    );

    return Stack(
      children: [
        list,
        const Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: AppSpace.x3,
          child: _EdgeFade(fromTop: true),
        ),
        const Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          height: AppSpace.x6,
          child: _EdgeFade(fromTop: false),
        ),
      ],
    );
  }

  Widget _row(
    ChatController chat,
    ConversationSummary item,
    String when, {
    required bool current,
    required bool live,
  }) {
    final row = _ChatRow(
      item: item,
      when: when,
      current: current,
      live: current && live,
      reduceMotion: _reduceMotion,
      onTap: () {
        unawaited(chat.openConversation(item));
        _close();
      },
      onLongPress: () => _openChatActions(chat, item),
    );
    if (item.isRemoteOnly) {
      return row;
    }
    return _SwipeToDelete(
      id: item.id,
      onArmed: () => chat.haptics?.tap(),
      onConfirm: () => confirmDeleteChat(context),
      onDeleted: () {
        setState(() => _dismissed.add(item.id));
        chat.deleteConversation(item);
      },
      child: row,
    );
  }

  Future<void> _openChatActions(
    ChatController chat,
    ConversationSummary item,
  ) async {
    chat.haptics?.tap();
    final when = _detailedWhen(
      item.updatedAt,
      use24h: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    await showFrankSheet<void>(
      context,
      builder: (sheetContext) {
        return FrankSheet(
          title: item.title,
          subtitle: when.isEmpty ? null : when,
          children: [
            SheetRow(
              icon: Icons.drive_file_rename_outline_rounded,
              label: 'Rename',
              onTap: () async {
                Navigator.of(sheetContext).pop();
                if (!mounted) {
                  return;
                }
                final next = await promptRenameChat(
                  context,
                  currentTitle: item.title,
                );
                if (next != null) {
                  await chat.renameConversation(item, next);
                }
              },
            ),
            SheetRow(
              icon: item.pinned
                  ? Icons.push_pin_outlined
                  : Icons.push_pin_rounded,
              label: item.pinned ? 'Unpin' : 'Pin',
              onTap: () {
                Navigator.of(sheetContext).pop();
                chat.togglePin(item);
              },
            ),
            // The danger row sits apart, as in the conversation and
            // account sheets.
            const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpace.x1),
              child: Divider(indent: 56, endIndent: 6),
            ),
            SheetRow(
              icon: Icons.delete_outline_rounded,
              label: 'Delete',
              danger: true,
              onTap: () async {
                Navigator.of(sheetContext).pop();
                if (!mounted) {
                  return;
                }
                if (await confirmDeleteChat(context)) {
                  setState(() => _dismissed.add(item.id));
                  await chat.deleteConversation(item);
                }
              },
            ),
          ],
        );
      },
    );
  }
}

/// Lifts the drawer's content above the keyboard. Only this padding follows
/// the keyboard's animation; the content inside is not rebuilt per frame.
class _KeyboardInset extends StatelessWidget {
  const _KeyboardInset({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: child,
    );
  }
}

/// Hides the footer while searching with the keyboard up.
class _HiddenWithKeyboard extends StatelessWidget {
  const _HiddenWithKeyboard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keyboard = MediaQuery.viewInsetsOf(context).bottom > 0;
    return keyboard ? const SizedBox.shrink() : child;
  }
}

/// The few controller values the drawer shows. Comparing snapshots keeps the
/// drawer still while a reply streams in behind it.
class _DrawerSnapshot {
  _DrawerSnapshot.of(ChatController chat)
    : history = chat.history,
      historyLoading = chat.historyLoading,
      conversationId = chat.conversationId,
      mood = chat.mood,
      toolLabel = chat.toolLabel,
      connected = chat.connected,
      loading = chat.loading,
      sending = chat.sending,
      modelLabel = chat.modelLabel,
      onDevice = chat.onDeviceDictation,
      error = chat.error;

  final List<ConversationSummary> history;
  final bool historyLoading;
  final String? conversationId;
  final AssistantMood mood;
  final String? toolLabel;
  final bool connected;
  final bool loading;
  final bool sending;
  final String? modelLabel;
  final bool onDevice;
  final String? error;

  bool sameAs(_DrawerSnapshot other) {
    return identical(history, other.history) &&
        historyLoading == other.historyLoading &&
        conversationId == other.conversationId &&
        mood == other.mood &&
        toolLabel == other.toolLabel &&
        connected == other.connected &&
        loading == other.loading &&
        sending == other.sending &&
        modelLabel == other.modelLabel &&
        onDevice == other.onDevice &&
        error == other.error;
  }
}

sealed class _Entry {
  const _Entry();

  Key get key;
}

class _LabelEntry extends _Entry {
  const _LabelEntry(this.label);

  final String label;

  @override
  Key get key => ValueKey('label:$label');
}

class _ChatEntry extends _Entry {
  const _ChatEntry(this.item, this.time);

  final ConversationSummary item;

  /// The short time label shown on the row.
  final String time;

  @override
  Key get key => ValueKey('chat:${item.id}');
}

class _HintEntry extends _Entry {
  const _HintEntry();

  @override
  Key get key => const ValueKey('hint');
}

/// The drawer's status is the header's ([chatStatusFor]): the same copy,
/// colors and dot, minus the header's "· tap to …" actions (the drawer line
/// is not tappable). Mic notices are not errors, as in the header.
ChatStatus _statusOf(_DrawerSnapshot snap) {
  final error = snap.error?.trim() ?? '';
  final status = chatStatusFor(
    mood: snap.mood,
    loading: snap.loading,
    connected: snap.connected,
    onDevice: snap.onDevice,
    toolLabel: snap.toolLabel,
    modelLabel: snap.modelLabel,
    showError: error.isNotEmpty && !isVoiceError(error),
  );
  final cut = status.label.indexOf(' · tap to ');
  if (cut < 0) {
    return status;
  }
  return ChatStatus(
    status.label.substring(0, cut),
    color: status.color,
    dot: status.dot,
    busy: status.busy,
  );
}

class _DrawerHeader extends StatelessWidget {
  const _DrawerHeader({
    required this.status,
    required this.mood,
    required this.lit,
    required this.level,
    required this.reduceMotion,
  });

  final ChatStatus status;
  final AssistantMood mood;
  final bool lit;
  final ValueListenable<double>? level;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x6,
        AppSpace.x3,
        AppSpace.x4,
        0,
      ),
      child: Row(
        children: [
          FrankMark(
            size: 32,
            active: lit,
            live: moodIsBusy(mood),
            listening: mood == AssistantMood.listening,
            intense: mood == AssistantMood.responding,
            mood: mood,
            level: level,
          ),
          const SizedBox(width: AppSpace.x3),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hermsy', style: AppText.title),
                const SizedBox(height: AppSpace.x0),
                _StatusLine(status: status, reduceMotion: reduceMotion),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status, required this.reduceMotion});

  final ChatStatus status;
  final bool reduceMotion;

  @override
  Widget build(BuildContext context) {
    final currentKey = ValueKey(status.label);
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 180),
      switchInCurve: AppMotion.standard,
      switchOutCurve: AppMotion.standard,
      layoutBuilder: (current, previous) {
        return Stack(
          alignment: Alignment.centerLeft,
          children: [...previous, ?current],
        );
      },
      transitionBuilder: (child, animation) {
        if (reduceMotion) {
          return FadeTransition(opacity: animation, child: child);
        }
        // New status rises in from below; the old one leaves upwards.
        final incoming = child.key == currentKey;
        final offset = Tween<Offset>(
          begin: Offset(0, incoming ? 0.35 : -0.35),
          end: Offset.zero,
        ).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(position: offset, child: child),
        );
      },
      child: Row(
        key: currentKey,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
              color: status.dot,
              shape: BoxShape.circle,
              boxShadow: [
                if (status.busy)
                  BoxShadow(
                    color: status.dot.withValues(alpha: 0.7),
                    blurRadius: 6,
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              status.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppText.caption.copyWith(color: status.color),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-width primary entry point: black glass with a gold hairline.
class _NewChatPill extends StatelessWidget {
  const _NewChatPill({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: 'New chat',
      excludeSemantics: true,
      child: Pressable(
        onTap: onTap,
        pressedScale: 0.97,
        child: AnimatedOpacity(
          duration: AppMotion.short,
          opacity: enabled ? 1 : 0.4,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: GlassPanel(
              blur: 0,
              radius: AppRadii.pill,
              color: AppColors.surface,
              borderColor: AppColors.gold.withValues(alpha: 0.42),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x4,
                vertical: 10,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.edit_square, size: 18, color: AppColors.gold),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Text(
                      'New chat',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.label.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchField extends StatefulWidget {
  const _SearchField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  State<_SearchField> createState() => _SearchFieldState();
}

class _SearchFieldState extends State<_SearchField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    _focus.addListener(_refresh);
  }

  @override
  void dispose() {
    _focus
      ..removeListener(_refresh)
      ..dispose();
    super.dispose();
  }

  void _refresh() => setState(() {});

  void _clear() {
    widget.controller.clear();
    widget.onChanged('');
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final hasText = widget.controller.text.isNotEmpty;
    return AnimatedContainer(
      duration: AppMotion.quick,
      curve: AppMotion.standard,
      constraints: const BoxConstraints(minHeight: 44),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadii.md),
        border: Border.all(
          color: _focus.hasFocus
              ? AppColors.gold.withValues(alpha: 0.45)
              : AppColors.hairline,
        ),
      ),
      child: Row(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: AppSpace.x3, right: 10),
            child: Icon(Icons.search_rounded, size: 20, color: AppColors.hint),
          ),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: _focus,
              onChanged: (value) {
                widget.onChanged(value);
                setState(() {});
              },
              textInputAction: TextInputAction.search,
              style: AppText.label.copyWith(fontWeight: FontWeight.w400),
              decoration: InputDecoration(
                hintText: 'Search chats',
                hintStyle: AppText.label.copyWith(
                  color: AppColors.hint,
                  fontWeight: FontWeight.w400,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: InputBorder.none,
              ),
            ),
          ),
          AnimatedSwitcher(
            duration: AppMotion.quick,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1).animate(animation),
                  child: child,
                ),
              );
            },
            child: hasText
                ? _ClearButton(key: const ValueKey('clear'), onTap: _clear)
                : const SizedBox(key: ValueKey('none'), width: AppSpace.x3),
          ),
        ],
      ),
    );
  }
}

class _ClearButton extends StatelessWidget {
  const _ClearButton({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Clear search',
      child: Semantics(
        button: true,
        label: 'Clear search',
        excludeSemantics: true,
        child: InkResponse(
          onTap: onTap,
          radius: 20,
          highlightColor: Colors.transparent,
          child: SizedBox(
            width: 44,
            height: 44,
            child: Icon(Icons.close_rounded, size: 18, color: AppColors.hint),
          ),
        ),
      ),
    );
  }
}

/// One conversation: unboxed; the current chat gets a soft fill and a gold
/// bar on its leading edge.
class _ChatRow extends StatelessWidget {
  const _ChatRow({
    required this.item,
    required this.when,
    required this.current,
    required this.live,
    required this.reduceMotion,
    required this.onTap,
    required this.onLongPress,
  });

  final ConversationSummary item;
  final String when;
  final bool current;

  /// Frank is working in this chat right now.
  final bool live;
  final bool reduceMotion;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadii.md);
    // One node per row: title, time, preview, and both actions together.
    return MergeSemantics(
      child: Semantics(
        selected: current,
        onLongPressHint: 'Rename, pin, or delete',
        child: Material(
          color: current ? AppColors.veil(0x0A) : Colors.transparent,
          borderRadius: radius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress,
            highlightColor: AppColors.veil(0x0D),
            splashColor: AppColors.veil(0x0F),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.x3,
                      vertical: 10,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            if (item.pinned) ...[
                              Icon(
                                Icons.push_pin_rounded,
                                size: 14,
                                color: AppColors.gold,
                              ),
                              const SizedBox(width: 6),
                            ],
                            Expanded(
                              child: Text(
                                item.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppText.label.copyWith(
                                  fontWeight: current
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                            if (live || when.isNotEmpty)
                              const SizedBox(width: AppSpace.x3),
                            if (live)
                              _LiveDot(reduceMotion: reduceMotion)
                            else if (when.isNotEmpty)
                              Text(
                                when,
                                style: AppText.tabular.copyWith(
                                  color: AppColors.hint,
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        _Preview(item.preview),
                      ],
                    ),
                  ),
                ),
                if (current)
                  Positioned(
                    left: 0,
                    top: AppSpace.x4,
                    bottom: AppSpace.x4,
                    child: Container(
                      width: 2,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [AppColors.goldBright, AppColors.goldDeep],
                        ),
                        borderRadius: BorderRadius.circular(AppRadii.pill),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.gold.withValues(alpha: 0.55),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview(this.preview);

  final String preview;

  static const _draft = 'Draft';

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(color: AppColors.hint, fontSize: 13, height: 1.3);
    final text = preview.trim();
    final span = text.startsWith('$_draft · ')
        ? TextSpan(
            children: [
              TextSpan(
                text: _draft,
                style: TextStyle(
                  color: AppColors.gold.withValues(alpha: 0.9),
                  fontWeight: FontWeight.w600,
                ),
              ),
              TextSpan(text: text.substring(_draft.length)),
            ],
          )
        : TextSpan(text: text.isEmpty ? 'No messages' : text);
    return Text.rich(
      span,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: style,
    );
  }
}

/// A small aurora dot that breathes while Frank works in the current chat.
/// It only exists while Frank is busy, so its loop stops with the reply.
class _LiveDot extends StatefulWidget {
  const _LiveDot({required this.reduceMotion});

  final bool reduceMotion;

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
    value: 1,
  );
  late final CurvedAnimation _eased = CurvedAnimation(
    parent: _breath,
    curve: Curves.easeInOut,
  );
  late final Animation<double> _opacity = Tween<double>(
    begin: 0.4,
    end: 1,
  ).animate(_eased);

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _LiveDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.reduceMotion) {
      _breath
        ..stop()
        ..value = 1;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _eased.dispose();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: AppGradients.aurora,
            boxShadow: [
              BoxShadow(
                color: AppColors.ion.withValues(alpha: 0.5),
                blurRadius: 6,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Swipe left to delete, behind the existing confirm. The bin wakes as the
/// row nears the threshold and pops (with a tick) once letting go deletes.
class _SwipeToDelete extends StatefulWidget {
  const _SwipeToDelete({
    required this.id,
    required this.onConfirm,
    required this.onDeleted,
    required this.onArmed,
    required this.child,
  });

  final String id;
  final Future<bool> Function() onConfirm;
  final VoidCallback onDeleted;
  final VoidCallback onArmed;
  final Widget child;

  @override
  State<_SwipeToDelete> createState() => _SwipeToDeleteState();
}

class _SwipeToDeleteState extends State<_SwipeToDelete> {
  static const _threshold = 0.35;

  final _progress = ValueNotifier<double>(0);
  final _armed = ValueNotifier<bool>(false);

  @override
  void dispose() {
    _progress.dispose();
    _armed.dispose();
    super.dispose();
  }

  void _onUpdate(DismissUpdateDetails details) {
    _progress.value = details.progress;
    if (details.reached != details.previousReached) {
      _armed.value = details.reached;
      if (details.reached) {
        widget.onArmed();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: ValueKey('swipe:${widget.id}'),
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: _threshold},
      confirmDismiss: (_) => widget.onConfirm(),
      onUpdate: _onUpdate,
      onDismissed: (_) => widget.onDeleted(),
      background: _DeleteBackdrop(progress: _progress, armed: _armed),
      child: widget.child,
    );
  }
}

class _DeleteBackdrop extends StatelessWidget {
  const _DeleteBackdrop({required this.progress, required this.armed});

  final ValueListenable<double> progress;
  final ValueListenable<bool> armed;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: armed,
      builder: (context, isArmed, child) {
        return AnimatedContainer(
          duration: AppMotion.quick,
          curve: AppMotion.standard,
          alignment: Alignment.centerRight,
          padding: const EdgeInsets.only(right: AppSpace.x5),
          decoration: BoxDecoration(
            color: AppColors.signal.withValues(alpha: isArmed ? 0.24 : 0.16),
            borderRadius: BorderRadius.circular(AppRadii.md),
          ),
          child: AnimatedScale(
            duration: AppMotion.short,
            curve: isArmed ? Curves.easeOutBack : AppMotion.standard,
            scale: isArmed ? 1.1 : 0.85,
            child: child,
          ),
        );
      },
      child: ValueListenableBuilder<double>(
        valueListenable: progress,
        builder: (context, value, child) {
          return Opacity(
            opacity: (value / _SwipeToDeleteState._threshold).clamp(0.0, 1.0),
            child: child,
          );
        },
        child: Icon(
          Icons.delete_outline_rounded,
          color: AppColors.danger,
          size: 22,
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.searching});

  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: const Alignment(0, -0.4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpace.x8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconTile(
              icon: searching
                  ? Icons.search_off_rounded
                  : Icons.chat_bubble_outline_rounded,
              size: 44,
              color: AppColors.hint,
            ),
            const SizedBox(height: AppSpace.x3),
            Text(
              searching ? 'No chats match.' : 'No earlier conversations yet.',
              textAlign: TextAlign.center,
              style: AppText.bodySmall.copyWith(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }
}

class _DrawerFooter extends StatelessWidget {
  const _DrawerFooter({required this.onSettings, this.onInbox, this.onLock});

  final VoidCallback onSettings;
  final VoidCallback? onInbox;
  final VoidCallback? onLock;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpace.x3,
        0,
        AppSpace.x3,
        AppSpace.x2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Divider(height: 1, thickness: 1, color: AppColors.hairline),
          const SizedBox(height: 6),
          if (onInbox != null)
            ValueListenableBuilder<int>(
              valueListenable: DeliveryInbox.unread,
              builder: (context, unread, _) => _FooterRow(
                leading: Icon(
                  Icons.inbox_rounded,
                  size: 20,
                  color: AppColors.secondary,
                ),
                label: 'Inbox',
                semanticsValue: unread > 0 ? '$unread unread' : null,
                trailing: unread > 0 ? _CountPill(unread) : null,
                onTap: onInbox!,
              ),
            ),
          Row(
            children: [
              Expanded(
                child: _FooterRow(
                  leading: Icon(
                    Icons.settings_outlined,
                    size: 20,
                    color: AppColors.secondary,
                  ),
                  label: 'Settings',
                  onTap: onSettings,
                ),
              ),
              if (onLock != null) ...[
                const SizedBox(width: AppSpace.x1),
                FrankIconButton(
                  icon: Icons.lock_outline_rounded,
                  tooltip: 'Lock Hermsy',
                  onPressed: onLock,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// How many are unread: a small gold pill.
class _CountPill extends StatelessWidget {
  const _CountPill(this.count);

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 22),
      height: 22,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(AppRadii.pill),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: AppText.tabular.copyWith(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.onGold,
        ),
      ),
    );
  }
}

class _FooterRow extends StatelessWidget {
  const _FooterRow({
    required this.leading,
    required this.label,
    required this.onTap,
    this.trailing,
    this.semanticsValue,
  });

  final Widget leading;
  final String label;
  final VoidCallback onTap;

  /// Shown before the chevron (the unread count).
  final Widget? trailing;
  final String? semanticsValue;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      value: semanticsValue,
      excludeSemantics: semanticsValue != null,
      child: Material(
        type: MaterialType.transparency,
        borderRadius: BorderRadius.circular(AppRadii.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          highlightColor: AppColors.veil(0x0D),
          splashColor: AppColors.veil(0x0F),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: AppSpace.minTouch),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpace.x3,
                vertical: AppSpace.x2,
              ),
              child: Row(
                children: [
                  SizedBox(width: 20, child: Center(child: leading)),
                  const SizedBox(width: 14),
                  Expanded(child: Text(label, style: AppText.label)),
                  if (trailing != null) ...[
                    trailing!,
                    const SizedBox(width: AppSpace.x2),
                  ],
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: AppColors.hint,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fades and slides a list entry in on open, 30ms after the one above it.
/// Static once the entrance has played.
class _Stagger extends StatelessWidget {
  const _Stagger({
    super.key,
    required this.animation,
    required this.step,
    required this.child,
  });

  final Animation<double> animation;

  /// 0 for the first entry; capped at [_staggerRows] - 1.
  final int step;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final total = _staggerStep * (_staggerRows - 1) + _rowEnter;
    final start = (_staggerStep * step).inMicroseconds / total.inMicroseconds;
    final end =
        (_staggerStep * step + _rowEnter).inMicroseconds / total.inMicroseconds;
    final curve = Interval(start, end.clamp(0.0, 1.0), curve: AppMotion.enter);
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = curve.transform(animation.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(-8 * (1 - t), 0),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Softens the list where it scrolls under the search field and the footer.
class _EdgeFade extends StatelessWidget {
  const _EdgeFade({required this.fromTop});

  final bool fromTop;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
            end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
            colors: [AppColors.glow, AppColors.glow.withValues(alpha: 0)],
          ),
        ),
      ),
    );
  }
}

/// A 1px light along the drawer's rounded right edge (light edges instead of
/// shadows on black).
class _EdgeLightPainter extends CustomPainter {
  const _EdgeLightPainter({required this.radius});

  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final edge = RRect.fromRectAndCorners(
      rect,
      topRight: Radius.circular(radius),
      bottomRight: Radius.circular(radius),
    ).deflate(0.5);
    canvas
      ..save()
      ..clipRect(Rect.fromLTRB(size.width - radius, 0, size.width, size.height))
      ..drawRRect(
        edge,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = AppColors.hairline,
      )
      ..restore();
  }

  @override
  bool shouldRepaint(covariant _EdgeLightPainter oldDelegate) {
    return oldDelegate.radius != radius;
  }
}
