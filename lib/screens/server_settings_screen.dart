import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../config/app_config.dart';
import '../services/hermes_client.dart';
import 'scan_connect_screen.dart';
import '../theme/app_theme.dart';
import '../widgets/frank_backdrop.dart';
import '../widgets/plugin_setup.dart';
import '../widgets/ui/frank_ui.dart';

/// Opens the camera and returns the address and key a QR code holds.
Future<({String url, String key})?> scanConnectCode(BuildContext context) =>
    Navigator.of(context).push<({String url, String key})>(
      MaterialPageRoute(builder: (_) => const ScanConnectScreen()),
    );

class ServerSettingsScreen extends StatefulWidget {
  const ServerSettingsScreen({
    super.key,
    required this.initial,
    required this.onSave,
    this.verify,
    this.scan = scanConnectCode,
  });

  final AppConfig initial;
  final Future<void> Function(AppConfig config) onSave;
  final Future<void> Function(AppConfig config)? verify;

  /// Reads the QR code from `hermes-spawn connect` (tests pass their own).
  final Future<({String url, String key})?> Function(BuildContext context) scan;

  @override
  State<ServerSettingsScreen> createState() => _ServerSettingsScreenState();
}

class _ServerSettingsScreenState extends State<ServerSettingsScreen> {
  late final TextEditingController _url;
  late final TextEditingController _key;
  final _urlFocus = FocusNode(debugLabel: 'server url');
  final _keyFocus = FocusNode(debugLabel: 'api key');
  var _hideKey = true;
  var _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _url = TextEditingController(text: widget.initial.baseUrl);
    _key = TextEditingController(text: widget.initial.apiKey);
  }

  @override
  void dispose() {
    _url.dispose();
    _key.dispose();
    _urlFocus.dispose();
    _keyFocus.dispose();
    super.dispose();
  }

  /// Fills both fields from the QR code, then checks and saves as usual.
  Future<void> _scan() async {
    final link = await widget.scan(context);
    if (link == null || !mounted) {
      return;
    }
    setState(() {
      _url.text = link.url;
      _key.text = link.key;
      _error = null;
    });
    await _save();
  }

  Future<void> _save() async {
    if (_saving) {
      return;
    }
    final next = AppConfig(
      baseUrl: AppConfig.normalizeBaseUrl(_url.text),
      apiKey: _key.text.trim(),
    );
    if (!next.looksConfigured) {
      setState(() => _error = 'Enter the HTTPS URL and API key.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      if (widget.verify != null) {
        await widget.verify!(next);
      } else {
        final client = HermesClient(baseUrl: next.baseUrl, apiKey: next.apiKey);
        try {
          await client.verifyAccess();
        } finally {
          client.close();
        }
      }
      await widget.onSave(next);
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (err) {
      if (!mounted) {
        return;
      }
      setState(() {
        _saving = false;
        _error = _describe(err);
      });
    }
  }

  /// Plain words for the failures people actually hit; anything else keeps
  /// Hermes' own message.
  static String _describe(Object err) {
    if (err is TimeoutException) {
      return 'Hermes didn\'t answer in time. Check the URL and try again.';
    }
    if (err is TlsException) {
      return 'The secure connection failed. Check that the URL uses HTTPS '
          'with a valid certificate.';
    }
    if (err is SocketException) {
      return 'Can\'t reach that address. Check the URL and your connection.';
    }
    final text = err.toString();
    const prefix = 'Exception: ';
    return text.startsWith(prefix) ? text.substring(prefix.length) : text;
  }

  void _clearError() {
    if (_error != null) {
      setState(() => _error = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final side = math.max(AppSpace.gutter, (media.size.width - 640) / 2);
    return FrankBackdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: CustomScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          slivers: [
            const LargeTitleSliverBar(title: 'Hermes'),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                side + media.padding.left,
                AppSpace.x1,
                side + media.padding.right,
                AppSpace.x8 + media.padding.bottom,
              ),
              sliver: SliverList.list(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 0, 4, 20),
                    child: Text(
                      'Hermsy talks to your own Hermes server. On the server, '
                      'run  hermes-spawn connect <name>  and scan the code it '
                      'shows, or enter the address and key. The key is kept '
                      'in this phone\'s secure storage.',
                      style: TextStyle(
                        color: AppColors.secondary,
                        fontSize: 15,
                        height: 1.47,
                      ),
                    ),
                  ),
                  if (widget.initial.looksConfigured)
                    GhostButton(
                      label: 'Scan QR code',
                      icon: Icons.qr_code_scanner_rounded,
                      expanded: true,
                      onPressed: _saving ? null : _scan,
                    )
                  else
                    GoldButton(
                      label: 'Scan QR code',
                      icon: Icons.qr_code_scanner_rounded,
                      onPressed: _saving ? null : _scan,
                    ),
                  const SizedBox(height: AppSpace.x6),
                  _Field(
                    label: 'Server URL',
                    controller: _url,
                    focusNode: _urlFocus,
                    hint: 'https://your-vps.example',
                    keyboardType: TextInputType.url,
                    textInputAction: TextInputAction.next,
                    invalid: _error != null && _url.text.trim().isEmpty,
                    onChanged: (_) => _clearError(),
                    onSubmitted: (_) => _keyFocus.requestFocus(),
                  ),
                  const SizedBox(height: AppSpace.x5),
                  _Field(
                    label: 'API key',
                    controller: _key,
                    focusNode: _keyFocus,
                    hint: 'Same as API_SERVER_KEY',
                    obscure: _hideKey,
                    monospace: true,
                    textInputAction: TextInputAction.done,
                    invalid: _error != null && _key.text.trim().isEmpty,
                    onChanged: (_) => _clearError(),
                    onSubmitted: (_) => _save(),
                    suffix: FrankIconButton(
                      icon: _hideKey
                          ? Icons.visibility_rounded
                          : Icons.visibility_off_rounded,
                      tooltip: _hideKey ? 'Show key' : 'Hide key',
                      size: 20,
                      color: AppColors.hint,
                      onPressed: () => setState(() => _hideKey = !_hideKey),
                    ),
                  ),
                  _ErrorLine(error: _error),
                  const SizedBox(height: AppSpace.x8),
                  GoldButton(
                    label: _saving ? 'Checking Hermes…' : 'Save and check',
                    busy: _saving,
                    onPressed: _save,
                  ),
                  const SizedBox(height: AppSpace.x3),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.x4,
                    ),
                    child: Text(
                      'Saving checks /health and the key, then starts a new '
                      'chat.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.hint,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  ),
                  if (widget.initial.looksConfigured) ...[
                    const SizedBox(height: AppSpace.x8),
                    PluginSetupSection(config: widget.initial),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A labeled 52dp field on surface black. Focus draws a gold hairline with a
/// soft gold glow; [invalid] edges it in signal red.
class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    required this.focusNode,
    required this.hint,
    this.keyboardType,
    this.textInputAction,
    this.obscure = false,
    this.monospace = false,
    this.invalid = false,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final bool obscure;
  final bool monospace;
  final bool invalid;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;

  static final _focusGlow = [
    BoxShadow(
      color: AppColors.gold.withValues(alpha: 0.16),
      blurRadius: 18,
      spreadRadius: -2,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final textStyle = monospace
        ? AppText.code.copyWith(
            color: AppColors.text,
            fontSize: 15,
            height: 1.4,
          )
        : TextStyle(color: AppColors.text, fontSize: 16, height: 1.4);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MicroLabel(label),
        ListenableBuilder(
          listenable: focusNode,
          builder: (context, child) {
            final focused = focusNode.hasFocus;
            final edge = focused
                ? AppColors.gold.withValues(alpha: 0.6)
                : invalid
                ? AppColors.signal.withValues(alpha: 0.55)
                : AppColors.hairline;
            return AnimatedContainer(
              duration: AppMotion.short,
              curve: AppMotion.standard,
              constraints: const BoxConstraints(minHeight: 52),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadii.md),
                border: Border.all(color: edge),
                boxShadow: focused ? _focusGlow : const [],
              ),
              alignment: Alignment.centerLeft,
              child: child,
            );
          },
          child: TextField(
            controller: controller,
            focusNode: focusNode,
            obscureText: obscure,
            autocorrect: false,
            enableSuggestions: false,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            onChanged: onChanged,
            onSubmitted: onSubmitted,
            style: textStyle,
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: textStyle.copyWith(color: AppColors.hint),
              border: InputBorder.none,
              isDense: true,
              contentPadding: EdgeInsets.fromLTRB(
                16,
                15,
                suffix == null ? 16 : 4,
                15,
              ),
              suffixIcon: suffix,
            ),
          ),
        ),
      ],
    );
  }
}

/// The inline error under the fields. It grows in rather than pushing the
/// button down in one jump, and is announced to screen readers.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.error});

  final String? error;

  @override
  Widget build(BuildContext context) {
    final error = this.error;
    return AnimatedSize(
      duration: AppMotion.reduced(context) ? Duration.zero : AppMotion.short,
      curve: AppMotion.standard,
      alignment: Alignment.topCenter,
      child: error == null
          ? const SizedBox(width: double.infinity)
          : Padding(
              padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
              child: Semantics(
                liveRegion: true,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Icon(
                        Icons.error_outline_rounded,
                        color: AppColors.danger,
                        size: 16,
                      ),
                    ),
                    const SizedBox(width: AppSpace.x2),
                    Expanded(
                      child: Text(
                        error,
                        style: TextStyle(
                          color: AppColors.danger,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }
}
