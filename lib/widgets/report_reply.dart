import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_version.dart';
import 'ui/frank_ui.dart';

/// Where reports of AI replies go: illbytes, who make Frank.
const reportEmail = 'support@illbytes.com';

/// Why a reply is being reported.
const reportReasons = [
  'Offensive or hateful',
  'Harmful or dangerous',
  'Sexual content',
  'False or misleading',
  'Something else',
];

/// The email a report opens: the reason, the reply itself, and the app
/// version, ready for the person to add a note and send. Nothing is sent
/// without them.
Uri reportEmailUri({
  required String reason,
  required String reply,
  required DateTime sentAt,
  String source = 'chat reply',
}) {
  final text = reply.trim();
  final clipped = text.length > 3000 ? '${text.substring(0, 3000)}…' : text;
  final subject = 'Hermsy report: $reason';
  final body =
      'Reason: $reason\n'
      'What: a $source, ${sentAt.toLocal().toIso8601String().substring(0, 16).replaceFirst('T', ' ')}\n'
      '\n'
      'The reply:\n'
      '$clipped\n'
      '\n'
      'Anything else you want to tell us:\n'
      '\n'
      '\n'
      '--\n'
      'Hermsy $appVersion';
  return Uri(
    scheme: 'mailto',
    path: reportEmail,
    // Encoded by hand: Uri's query encoding turns spaces into "+", which
    // mail apps show as plus signs.
    query:
        'subject=${Uri.encodeComponent(subject)}'
        '&body=${Uri.encodeComponent(body)}',
  );
}

/// Asks why [reply] is being reported, then opens the report as an email.
/// Without an email app the report is copied to the clipboard instead.
Future<void> reportReply(
  BuildContext context, {
  required String reply,
  required DateTime sentAt,
  String source = 'chat reply',
}) async {
  final reason = await showFrankSheet<String>(
    context,
    builder: (sheetContext) => FrankSheet(
      // Five reasons and a note: scrolls on a short screen.
      scrollable: true,
      title: 'Report this reply',
      subtitle:
          'Tell illbytes, who make Hermsy, what is wrong with it. Your email '
          'app opens with the reply in it; nothing is sent until you send it.',
      children: [
        for (final reason in reportReasons)
          SheetRow(
            icon: reason == 'Something else'
                ? Icons.more_horiz_rounded
                : Icons.outlined_flag_rounded,
            label: reason,
            onTap: () => Navigator.of(sheetContext).pop(reason),
          ),
      ],
    ),
  );
  if (reason == null || !context.mounted) {
    return;
  }
  final uri = reportEmailUri(
    reason: reason,
    reply: reply,
    sentAt: sentAt,
    source: source,
  );
  final messenger = ScaffoldMessenger.maybeOf(context);
  var opened = false;
  try {
    opened = await launchUrl(uri);
  } catch (_) {}
  if (!opened) {
    final body = Uri.decodeComponent(uri.query.split('&body=').last);
    await Clipboard.setData(ClipboardData(text: body));
  }
  messenger
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Thanks. Send the email to finish the report.'
              : 'No email app found. The report is copied: send it to '
                    '$reportEmail.',
        ),
      ),
    );
}
