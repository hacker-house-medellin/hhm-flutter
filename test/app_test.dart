import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/app.dart';
import 'package:hhm_flutter/src/config/public_config.dart';

void main() {
  testWidgets('shows safe visitor and presence boundaries', (tester) async {
    tester.view.physicalSize = const Size(1200, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final config = PublicConfig(
      apiBaseUri: Uri.parse('https://api.hhm.example'),
      sharedAuthIssuer: Uri.parse('https://auth.hhm.example'),
      supabaseUri: Uri.parse('https://project.supabase.co'),
      supabasePublishableKey: 'sb_publishable_test',
      otelEndpoint: Uri.parse('https://telemetry.hhm.example/v1/traces'),
      releaseEnvironment: 'test',
    );

    await tester.pumpWidget(HhmApp(config: config));

    expect(find.text('Resident identity'), findsOneWidget);
    expect(find.text('Visitor QR'), findsOneWidget);
    expect(find.text('Proximity assistance'), findsOneWidget);
    expect(find.text('Nearby peer exchange'), findsOneWidget);
    expect(find.textContaining('Bluetooth is never'), findsOneWidget);
    expect(find.textContaining('Codes rotate every minute'), findsOneWidget);
    expect(find.textContaining('proximity never grants trust'), findsOneWidget);

    final signInButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Scan sign-in QR'),
    );
    expect(signInButton.onPressed, isNull);

    final proximitySwitch = tester.widget<SwitchListTile>(
      find.byType(SwitchListTile),
    );
    expect(proximitySwitch.value, isFalse);
    expect(proximitySwitch.onChanged, isNull);

    final peerButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Choose nearby peer'),
    );
    expect(peerButton.onPressed, isNull);
  });
}
