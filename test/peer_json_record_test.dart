import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hhm_flutter/src/bluetooth/peer_json_record.dart';
import 'package:hhm_flutter/src/bluetooth/peer_payload.dart';

void main() {
  const codec = PeerJsonRecordCodec();
  final now = DateTime.parse('2026-08-24T16:01:00Z');

  Map<String, Object?> fixtures() =>
      jsonDecode(
            File(
              'protocol/fixtures/v1/p2p-json-records.json',
            ).readAsStringSync(),
          )
          as Map<String, Object?>;

  Uint8List encode(Object? value) =>
      Uint8List.fromList(utf8.encode(jsonEncode(value)));

  test('decodes each canonical closed JSON record', () {
    final fixture = fixtures();
    final contact = codec.decode(
      payloadType: PeerPayloadType.contactCard,
      plaintext: encode(fixture['contact_card']),
      now: now,
    );
    final message = codec.decode(
      payloadType: PeerPayloadType.residentMessage,
      plaintext: encode(fixture['resident_message']),
      now: now,
    );
    final receipt = codec.decode(
      payloadType: PeerPayloadType.receipt,
      plaintext: encode(fixture['receipt']),
      now: now,
    );

    expect(contact, isA<ContactCard>());
    expect(message, isA<ResidentMessage>());
    expect(receipt, isA<PeerReceipt>());
    expect(contact.payloadType, PeerPayloadType.contactCard);
    expect(message.payloadType, PeerPayloadType.residentMessage);
    expect(receipt.payloadType, PeerPayloadType.receipt);
  });

  test('envelope type must match the decrypted record schema', () {
    final fixture = fixtures();
    expect(
      () => codec.decode(
        payloadType: PeerPayloadType.contactCard,
        plaintext: encode(fixture['resident_message']),
        now: now,
      ),
      throwsFormatException,
    );
  });

  test('rejects unknown fields, insecure links, and long lifetimes', () {
    final fixture = fixtures();
    final contact = Map<String, Object?>.from(
      fixture['contact_card']! as Map<String, Object?>,
    );
    contact['html'] = '<script>unsafe()</script>';
    expect(
      () => codec.decode(
        payloadType: PeerPayloadType.contactCard,
        plaintext: encode(contact),
        now: now,
      ),
      throwsFormatException,
    );

    final insecure = Map<String, Object?>.from(
      fixture['contact_card']! as Map<String, Object?>,
    );
    final fields = (insecure['fields']! as List<Object?>)
        .map((item) => Map<String, Object?>.from(item! as Map<String, Object?>))
        .toList();
    fields[1]['value'] = 'http://nearby-peer/profile';
    insecure['fields'] = fields;
    expect(
      () => codec.decode(
        payloadType: PeerPayloadType.contactCard,
        plaintext: encode(insecure),
        now: now,
      ),
      throwsFormatException,
    );

    final message = Map<String, Object?>.from(
      fixture['resident_message']! as Map<String, Object?>,
    );
    message['expires_at'] = '2026-08-24T16:11:06Z';
    expect(
      () => codec.decode(
        payloadType: PeerPayloadType.residentMessage,
        plaintext: encode(message),
        now: now,
      ),
      throwsFormatException,
    );
  });

  test('strict decoder rejects duplicate keys before jsonDecode', () {
    final duplicate = Uint8List.fromList(
      utf8.encode(
        '{"schema":"hhm.receipt.v1","schema":"hhm.contact-card.v1",'
        '"record_id":"70920cff-cabe-4f87-8f7a-775fb02c9f49",'
        '"acknowledged_record_id":"d6f61ed1-6ee6-49b5-a125-e94d495ba5f2",'
        '"status":"received","created_at":"2026-08-24T16:00:07Z",'
        '"expires_at":"2026-08-24T16:02:07Z"}',
      ),
    );
    expect(
      () => codec.decode(
        payloadType: PeerPayloadType.receipt,
        plaintext: duplicate,
        now: now,
      ),
      throwsFormatException,
    );
  });
}
