import 'package:flutter/material.dart';

import 'config/public_config.dart';

final class HhmApp extends StatelessWidget {
  const HhmApp({
    required this.config,
    this.onVisitorSignInScan,
    this.onVisitorSignOutScan,
    this.onProximityConsentChanged,
    this.onChooseNearbyPeer,
    super.key,
  });

  final PublicConfig config;
  final VoidCallback? onVisitorSignInScan;
  final VoidCallback? onVisitorSignOutScan;
  final ValueChanged<bool>? onProximityConsentChanged;
  final VoidCallback? onChooseNearbyPeer;

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'HHM',
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff006c51),
        brightness: Brightness.light,
      ),
      useMaterial3: true,
    ),
    home: HhmHomeScreen(
      config: config,
      onVisitorSignInScan: onVisitorSignInScan,
      onVisitorSignOutScan: onVisitorSignOutScan,
      onProximityConsentChanged: onProximityConsentChanged,
      onChooseNearbyPeer: onChooseNearbyPeer,
    ),
  );
}

final class HhmHomeScreen extends StatelessWidget {
  const HhmHomeScreen({
    required this.config,
    this.onVisitorSignInScan,
    this.onVisitorSignOutScan,
    this.onProximityConsentChanged,
    this.onChooseNearbyPeer,
    super.key,
  });

  final PublicConfig config;
  final VoidCallback? onVisitorSignInScan;
  final VoidCallback? onVisitorSignOutScan;
  final ValueChanged<bool>? onProximityConsentChanged;
  final VoidCallback? onChooseNearbyPeer;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Hacker House Medellín')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: <Widget>[
          Text(
            'House presence',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          Text(
            config.isConfigured
                ? 'Public endpoints are configured. Sign in to continue.'
                : 'This development build is offline until public endpoints '
                      'are configured.',
          ),
          const SizedBox(height: 20),
          const _CapabilityCard(
            icon: Icons.verified_user_outlined,
            title: 'Resident identity',
            body:
                'HHM requires both Supabase and Shared Auth assurance. '
                'Bluetooth is never used to prove identity.',
          ),
          const SizedBox(height: 12),
          _CapabilityCard(
            icon: Icons.qr_code_scanner,
            title: 'Visitor QR',
            body:
                'Scan a backend-issued sign-in or sign-out code. Codes rotate '
                'every minute and are accepted only after server verification.',
            footer: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: onVisitorSignInScan,
                  icon: const Icon(Icons.login),
                  label: const Text('Scan sign-in QR'),
                ),
                FilledButton.tonalIcon(
                  onPressed: onVisitorSignOutScan,
                  icon: const Icon(Icons.logout),
                  label: const Text('Scan sign-out QR'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          _CapabilityCard(
            icon: Icons.bluetooth_searching,
            title: 'Proximity assistance',
            body:
                'Opt in to BLE plus a second nearby signal. Evidence proposes '
                'a presence update; it cannot authenticate you or unlock a door.',
            footer: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('Allow proximity suggestions'),
              subtitle: const Text('Off by default; consent can be revoked.'),
              value: false,
              onChanged: onProximityConsentChanged,
            ),
          ),
          const SizedBox(height: 12),
          _CapabilityCard(
            icon: Icons.devices_other_outlined,
            title: 'Nearby peer exchange',
            body:
                'Choose a peer while this screen is in the foreground. '
                'Shared Auth and encrypted expiring sessions protect signed '
                'update metadata; proximity never grants trust or access.',
            footer: FilledButton.tonalIcon(
              onPressed: onChooseNearbyPeer,
              icon: const Icon(Icons.person_search_outlined),
              label: const Text('Choose nearby peer'),
            ),
          ),
          const SizedBox(height: 12),
          const _CapabilityCard(
            icon: Icons.monitor_heart_outlined,
            title: 'Privacy-safe operations',
            body:
                'Ores OTEL receives bounded operational outcomes only—never '
                'names, QR contents, tokens, beacon IDs, or precise location.',
          ),
        ],
      ),
    ),
  );
}

final class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({
    required this.icon,
    required this.title,
    required this.body,
    this.footer,
  });

  final IconData icon;
  final String title;
  final String body;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(body),
          if (footer != null) ...<Widget>[const SizedBox(height: 12), footer!],
        ],
      ),
    ),
  );
}
