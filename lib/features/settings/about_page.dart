import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

/// App information: version, developer and the open source repository.
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  /// Keep in sync with `version` in pubspec.yaml.
  static const String appVersion = '1.2.3';

  static const String developerName = 'Thirhythm';

  // Sample addresses, replace them with the real ones.
  static const String developerUrl = 'https://github.com/thirhythm';
  static const String repositoryUrl = 'https://github.com/thirhythm/bilihear';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('关于')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          const ListTile(
            title: Text('FlowingPod'),
            subtitle: Text('版本 $appVersion'),
          ),
          const Divider(height: 1),
          _LinkTile(
            icon: Icons.person_outline_rounded,
            title: '开发者',
            subtitle: developerName,
            url: developerUrl,
          ),
          const ListTile(
            leading: Icon(Icons.gavel_outlined),
            title: Text('开源协议'),
            subtitle: Text('GPLv3'),
          ),
          _LinkTile(
            icon: Icons.code_rounded,
            title: '开源仓库',
            subtitle: repositoryUrl,
            url: repositoryUrl,
          ),
        ],
      ),
    );
  }
}

/// List row that hands its [url] to the system browser.
class _LinkTile extends StatelessWidget {
  const _LinkTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.url,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String url;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: Icon(icon),
    title: Text(title),
    subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: const Icon(Icons.open_in_new_rounded, size: 18),
    onTap: () => _open(context, url),
  );

  Future<void> _open(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    var launched = false;
    try {
      launched = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } on Exception {
      launched = false;
    }
    if (!launched && context.mounted) {
      messenger.showSnackBar(SnackBar(content: Text('无法打开链接：$url')));
    }
  }
}
