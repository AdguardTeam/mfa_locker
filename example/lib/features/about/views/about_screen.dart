import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Screen that displays information about the application: icon, name, version,
/// copyright, and a link to the open-source licenses page.
class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('About'),
    ),
    body: SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            const FlutterLogo(size: 80),
            const SizedBox(height: 24),
            Text(
              _packageInfo?.appName ?? 'MFA Demo',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              _versionString,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              '© 2025 AdGuard. All rights reserved.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            TextButton(
              onPressed: () => showLicensePage(context: context),
              child: const Text('View License'),
            ),
          ],
        ),
      ),
    ),
  );

  String get _versionString {
    final info = _packageInfo;
    if (info == null) return '';
    final build = info.buildNumber.isNotEmpty ? ' (${info.buildNumber})' : '';
    return '${info.version}$build';
  }

  Future<void> _loadPackageInfo() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _packageInfo = info);
  }
}
