import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config/app_config.dart';
import '../services/relay_client.dart';
import '../theme/app_theme.dart';
import 'ui/frank_ui.dart';

/// The command that installs the plugin, shown when it is missing.
const pluginInstallCommand =
    'hermes plugins install illbytes/hermsy-hermes --enable';

/// The phone's time zone as an IANA name ("Europe/London"), or null.
Future<String?> phoneTimeZone() async {
  try {
    return await const MethodChannel(
      'frank/display',
    ).invokeMethod<String>('timeZone');
  } catch (_) {
    return null;
  }
}

/// What the Hermsy plugin on this Hermes can do, and one tap to set up the
/// Brief and the Chief of Staff. Without the plugin, how to install it.
class PluginSetupSection extends StatefulWidget {
  const PluginSetupSection({
    super.key,
    required this.config,
    this.clientFor,
    this.timeZone = phoneTimeZone,
  });

  final AppConfig config;
  final RelayClient Function(AppConfig config)? clientFor;
  final Future<String?> Function() timeZone;

  @override
  State<PluginSetupSection> createState() => _PluginSetupSectionState();
}

class _PluginSetupSectionState extends State<PluginSetupSection> {
  PluginStatus? _status;
  Object? _error;
  var _checking = true;
  String? _settingUp;

  RelayClient _client() => (widget.clientFor ?? RelayClient.new)(widget.config);

  @override
  void initState() {
    super.initState();
    _check();
  }

  Future<void> _check() async {
    setState(() {
      _checking = true;
      _error = null;
    });
    final client = _client();
    try {
      final status = await client.hello();
      if (mounted) {
        setState(() => _status = status);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _checking = false);
      }
    }
  }

  Future<void> _setUp({bool brief = false, bool chiefOfStaff = false}) async {
    setState(() {
      _settingUp = brief ? 'brief' : 'chief';
      _error = null;
    });
    final client = _client();
    try {
      final status = await client.setup(
        brief: brief,
        chiefOfStaff: chiefOfStaff,
        timezone: await widget.timeZone(),
      );
      if (mounted) {
        setState(() => _status = status);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = error);
      }
    } finally {
      client.close();
      if (mounted) {
        setState(() => _settingUp = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    final error = _error;
    final missing = error is RelayException && error.missing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MicroLabel('Hermsy plugin'),
        if (_checking && status == null)
          const FrankGroup(
            children: [
              FrankTile(
                icon: Icons.extension_rounded,
                title: 'Checking Hermes…',
              ),
            ],
          )
        else if (missing)
          _Missing(onRetry: _check)
        else if (status == null)
          FrankGroup(
            children: [
              FrankTile(
                icon: Icons.error_outline_rounded,
                title: 'Could not check the plugin',
                subtitle: '$error',
                trailing: GhostButton(
                  label: 'Retry',
                  height: 36,
                  onPressed: _check,
                ),
              ),
            ],
          )
        else ...[
          FrankGroup(
            children: [
              FrankTile(
                icon: Icons.extension_rounded,
                title: 'Connected',
                subtitle: 'Hermsy plugin ${status.version}',
              ),
              FrankTile(
                icon: Icons.notifications_active_rounded,
                title: 'Notifications',
                subtitle: status.push
                    ? 'Your phone is woken when Hermes sends something'
                    : 'Off on the server (HERMSY_PUSH_URL): the Inbox fills when you open Hermsy',
              ),
              FrankTile(
                icon: Icons.record_voice_over_rounded,
                title: 'Cloud voices',
                subtitle: status.voices.isEmpty
                    ? 'None: add OPENAI_API_KEY or ELEVENLABS_API_KEY to Hermes'
                    : status.voices.map(_providerName).join(', '),
              ),
            ],
          ),
          const SizedBox(height: AppSpace.x5),
          const MicroLabel('On a schedule'),
          FrankGroup(
            children: [
              _JobTile(
                icon: Icons.wb_sunny_rounded,
                title: 'Hermsy Brief',
                about: 'Your day at a glance, three times a day',
                job: status.brief,
                busy: _settingUp == 'brief',
                onSetUp: _settingUp == null ? () => _setUp(brief: true) : null,
              ),
              _JobTile(
                icon: Icons.assistant_rounded,
                title: 'Chief of Staff',
                about:
                    'Texts you when something needs you, and stays quiet otherwise',
                job: status.chiefOfStaff,
                busy: _settingUp == 'chief',
                onSetUp: _settingUp == null
                    ? () => _setUp(chiefOfStaff: true)
                    : null,
              ),
            ],
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
              child: Text(
                '$error',
                style: AppText.bodySmall.copyWith(color: AppColors.danger),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 0),
            child: Text(
              'Set-up jobs run at times in your time zone and send to Hermsy. '
              'Tell Hermes what matters to you ("from now on, always flag…") and '
              'it keeps your standing orders.',
              style: AppText.bodySmall.copyWith(color: AppColors.hint),
            ),
          ),
        ],
      ],
    );
  }

  static String _providerName(String id) => switch (id) {
    'openai' => 'OpenAI',
    'elevenlabs' => 'ElevenLabs',
    _ => id,
  };
}

class _JobTile extends StatelessWidget {
  const _JobTile({
    required this.icon,
    required this.title,
    required this.about,
    required this.job,
    required this.busy,
    required this.onSetUp,
  });

  final IconData icon;
  final String title;
  final String about;
  final PluginJob? job;
  final bool busy;
  final VoidCallback? onSetUp;

  @override
  Widget build(BuildContext context) {
    final job = this.job;
    return FrankTile(
      icon: icon,
      title: title,
      subtitle: job == null
          ? about
          : job.enabled
          ? 'Set up · runs ${job.schedule ?? 'on a schedule'} (server time)'
          : 'Set up, but paused on the server',
      trailing: job != null
          ? Icon(Icons.check_circle_rounded, color: AppColors.mint, size: 22)
          : GhostButton(
              label: busy ? 'Setting up…' : 'Set up',
              height: 36,
              onPressed: busy ? null : onSetUp,
            ),
    );
  }
}

class _Missing extends StatelessWidget {
  const _Missing({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return FrankGroup(
      dividerIndent: 0,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Not installed',
                style: AppText.label.copyWith(fontSize: 16),
              ),
              const SizedBox(height: 6),
              Text(
                'Chat and calls work without it. For the Inbox, notifications, '
                'the Brief and the Chief of Staff, run this where Hermes runs, '
                'then restart Hermes:',
                style: AppText.bodySmall.copyWith(fontSize: 13.5),
              ),
              const SizedBox(height: 10),
              _Command(text: pluginInstallCommand),
              const SizedBox(height: 12),
              GhostButton(label: 'Check again', height: 40, onPressed: onRetry),
            ],
          ),
        ),
      ],
    );
  }
}

class _Command extends StatelessWidget {
  const _Command({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.codeBg,
      borderRadius: BorderRadius.circular(AppRadii.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadii.sm),
        onTap: () {
          Clipboard.setData(ClipboardData(text: text));
          ScaffoldMessenger.maybeOf(
            context,
          )?.showSnackBar(const SnackBar(content: Text('Copied')));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              Expanded(
                child: SelectableText(
                  text,
                  style: AppText.bodySmall.copyWith(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: AppColors.text,
                  ),
                ),
              ),
              Icon(Icons.copy_rounded, size: 18, color: AppColors.hint),
            ],
          ),
        ),
      ),
    );
  }
}
