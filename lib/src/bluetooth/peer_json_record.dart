import 'dart:convert';
import 'dart:typed_data';

import '../protocol/strict_json.dart';
import 'peer_payload.dart';

const int maximumPeerJsonRecordBytes = 16 * 1024;

sealed class PeerJsonRecord {
  const PeerJsonRecord();

  PeerPayloadType get payloadType;
  DateTime get createdAt;
  DateTime get expiresAt;
  Map<String, Object?> toJson();
}

enum ContactFieldKind { github, matrix, website }

final class ContactField {
  ContactField({required this.kind, required this.value}) {
    _plainText('contact field', value, minimum: 1, maximum: 256);
    if (kind == ContactFieldKind.website) {
      final uri = Uri.tryParse(value);
      if (uri == null ||
          uri.scheme != 'https' ||
          !uri.hasAuthority ||
          uri.userInfo.isNotEmpty) {
        throw const FormatException('Contact website must be an HTTPS URL');
      }
    }
    if (kind == ContactFieldKind.matrix &&
        (!value.startsWith('@') || !value.contains(':'))) {
      throw const FormatException('Matrix contact shape is invalid');
    }
  }

  factory ContactField.fromJson(Map<String, Object?> json) {
    _requireKeys(json, required: const <String>{'kind', 'value'});
    return ContactField(
      kind: switch (_string(json, 'kind')) {
        'github' => ContactFieldKind.github,
        'matrix' => ContactFieldKind.matrix,
        'website' => ContactFieldKind.website,
        _ => throw const FormatException('Unknown contact field kind'),
      },
      value: _string(json, 'value'),
    );
  }

  final ContactFieldKind kind;
  final String value;

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind.name,
    'value': value,
  };
}

final class ContactCard extends PeerJsonRecord {
  ContactCard({
    required this.recordId,
    required this.displayAlias,
    required Iterable<ContactField> fields,
    required this.createdAt,
    required this.expiresAt,
  }) : fields = List.unmodifiable(fields) {
    _uuid('record_id', recordId);
    _plainText('display_alias', displayAlias, minimum: 1, maximum: 80);
    if (this.fields.length > 8) {
      throw const FormatException('Contact card exceeds 8 fields');
    }
  }

  factory ContactCard.fromJson(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    _requireKeys(
      json,
      required: const <String>{
        'schema',
        'record_id',
        'display_alias',
        'fields',
        'created_at',
        'expires_at',
      },
    );
    if (json['schema'] != PeerPayloadType.contactCard.wireName) {
      throw const FormatException('Unsupported contact card schema');
    }
    final rawFields = json['fields'];
    if (rawFields is! List<Object?>) {
      throw const FormatException('Contact fields must be an array');
    }
    final result = ContactCard(
      recordId: _string(json, 'record_id'),
      displayAlias: _string(json, 'display_alias'),
      fields: rawFields.map(
        (value) => ContactField.fromJson(_object(value, 'contact field')),
      ),
      createdAt: _instant(json, 'created_at'),
      expiresAt: _instant(json, 'expires_at'),
    );
    _recordWindow(result.createdAt, result.expiresAt, now);
    return result;
  }

  final String recordId;
  final String displayAlias;
  final List<ContactField> fields;
  @override
  final DateTime createdAt;
  @override
  final DateTime expiresAt;

  @override
  PeerPayloadType get payloadType => PeerPayloadType.contactCard;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'schema': payloadType.wireName,
    'record_id': recordId,
    'display_alias': displayAlias,
    'fields': fields.map((field) => field.toJson()).toList(growable: false),
    'created_at': _wireInstant(createdAt),
    'expires_at': _wireInstant(expiresAt),
  };
}

enum ResidentMessageTopic { chat, houseCoordination, support }

final class ResidentMessage extends PeerJsonRecord {
  ResidentMessage({
    required this.recordId,
    required this.topic,
    required this.text,
    this.replyTo,
    required this.createdAt,
    required this.expiresAt,
  }) {
    _uuid('record_id', recordId);
    if (replyTo case final value?) _uuid('reply_to', value);
    _plainText(
      'resident message',
      text,
      minimum: 1,
      maximum: 4096,
      allowNewlines: true,
    );
  }

  factory ResidentMessage.fromJson(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    _requireKeys(
      json,
      required: const <String>{
        'schema',
        'record_id',
        'topic',
        'format',
        'text',
        'created_at',
        'expires_at',
      },
      optional: const <String>{'reply_to'},
    );
    if (json['schema'] != PeerPayloadType.residentMessage.wireName ||
        json['format'] != 'plain_text') {
      throw const FormatException(
        'Resident messages must use the plain-text v1 schema',
      );
    }
    final result = ResidentMessage(
      recordId: _string(json, 'record_id'),
      topic: switch (_string(json, 'topic')) {
        'chat' => ResidentMessageTopic.chat,
        'house_coordination' => ResidentMessageTopic.houseCoordination,
        'support' => ResidentMessageTopic.support,
        _ => throw const FormatException('Unknown resident message topic'),
      },
      text: _string(json, 'text'),
      replyTo: json['reply_to'] == null ? null : _string(json, 'reply_to'),
      createdAt: _instant(json, 'created_at'),
      expiresAt: _instant(json, 'expires_at'),
    );
    _recordWindow(result.createdAt, result.expiresAt, now);
    return result;
  }

  final String recordId;
  final ResidentMessageTopic topic;
  final String text;
  final String? replyTo;
  @override
  final DateTime createdAt;
  @override
  final DateTime expiresAt;

  @override
  PeerPayloadType get payloadType => PeerPayloadType.residentMessage;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'schema': payloadType.wireName,
    'record_id': recordId,
    'topic': switch (topic) {
      ResidentMessageTopic.chat => 'chat',
      ResidentMessageTopic.houseCoordination => 'house_coordination',
      ResidentMessageTopic.support => 'support',
    },
    'format': 'plain_text',
    'text': text,
    'reply_to': ?replyTo,
    'created_at': _wireInstant(createdAt),
    'expires_at': _wireInstant(expiresAt),
  };
}

enum PeerReceiptStatus { received, declined, expired }

final class PeerReceipt extends PeerJsonRecord {
  PeerReceipt({
    required this.recordId,
    required this.acknowledgedRecordId,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
  }) {
    _uuid('record_id', recordId);
    _uuid('acknowledged_record_id', acknowledgedRecordId);
    if (recordId == acknowledgedRecordId) {
      throw const FormatException('Receipt cannot acknowledge itself');
    }
  }

  factory PeerReceipt.fromJson(
    Map<String, Object?> json, {
    required DateTime now,
  }) {
    _requireKeys(
      json,
      required: const <String>{
        'schema',
        'record_id',
        'acknowledged_record_id',
        'status',
        'created_at',
        'expires_at',
      },
    );
    if (json['schema'] != PeerPayloadType.receipt.wireName) {
      throw const FormatException('Unsupported peer receipt schema');
    }
    final result = PeerReceipt(
      recordId: _string(json, 'record_id'),
      acknowledgedRecordId: _string(json, 'acknowledged_record_id'),
      status: switch (_string(json, 'status')) {
        'received' => PeerReceiptStatus.received,
        'declined' => PeerReceiptStatus.declined,
        'expired' => PeerReceiptStatus.expired,
        _ => throw const FormatException('Unknown peer receipt status'),
      },
      createdAt: _instant(json, 'created_at'),
      expiresAt: _instant(json, 'expires_at'),
    );
    _recordWindow(result.createdAt, result.expiresAt, now);
    return result;
  }

  final String recordId;
  final String acknowledgedRecordId;
  final PeerReceiptStatus status;
  @override
  final DateTime createdAt;
  @override
  final DateTime expiresAt;

  @override
  PeerPayloadType get payloadType => PeerPayloadType.receipt;

  @override
  Map<String, Object?> toJson() => <String, Object?>{
    'schema': payloadType.wireName,
    'record_id': recordId,
    'acknowledged_record_id': acknowledgedRecordId,
    'status': status.name,
    'created_at': _wireInstant(createdAt),
    'expires_at': _wireInstant(expiresAt),
  };
}

final class PeerJsonRecordCodec {
  const PeerJsonRecordCodec();

  PeerJsonRecord decode({
    required PeerPayloadType payloadType,
    required Uint8List plaintext,
    required DateTime now,
  }) {
    final json = decodeStrictJsonObject(
      plaintext,
      maximumBytes: maximumPeerJsonRecordBytes,
    );
    return switch (payloadType) {
      PeerPayloadType.contactCard => ContactCard.fromJson(json, now: now),
      PeerPayloadType.residentMessage => ResidentMessage.fromJson(
        json,
        now: now,
      ),
      PeerPayloadType.receipt => PeerReceipt.fromJson(json, now: now),
      PeerPayloadType.fileManifest || PeerPayloadType.updateManifest =>
        throw const FormatException('Payload type is not a P2P JSON record'),
    };
  }

  Uint8List encode(PeerJsonRecord record, {required DateTime now}) {
    _recordWindow(record.createdAt, record.expiresAt, now);
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode(record.toJson())));
    if (bytes.isEmpty || bytes.length > maximumPeerJsonRecordBytes) {
      throw const FormatException('P2P JSON record size is invalid');
    }
    return bytes;
  }
}

void _requireKeys(
  Map<String, Object?> value, {
  required Set<String> required,
  Set<String> optional = const <String>{},
}) {
  final keys = value.keys.toSet();
  if (required.difference(keys).isNotEmpty ||
      keys.difference(required.union(optional)).isNotEmpty) {
    throw const FormatException('Document contains unknown or missing fields');
  }
}

Map<String, Object?> _object(Object? value, String name) {
  if (value is! Map<String, Object?>) {
    throw FormatException('$name must be an object');
  }
  return value;
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is! String) throw FormatException('$key must be a string');
  return value;
}

DateTime _instant(Map<String, Object?> json, String key) {
  final value = DateTime.tryParse(_string(json, key));
  if (value == null || !value.isUtc) {
    throw FormatException('$key must be a UTC timestamp');
  }
  return value;
}

String _wireInstant(DateTime value) => value.toUtc().toIso8601String();

void _uuid(String name, String value) {
  if (!RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
    caseSensitive: false,
  ).hasMatch(value)) {
    throw FormatException('$name must be a UUID');
  }
}

void _plainText(
  String name,
  String value, {
  required int minimum,
  required int maximum,
  bool allowNewlines = false,
}) {
  final length = value.runes.length;
  final invalidControl = value.runes.any(
    (code) =>
        code == 0 ||
        (code < 0x20 &&
            !(allowNewlines && const <int>{0x09, 0x0a, 0x0d}.contains(code))) ||
        code == 0x7f,
  );
  if (length < minimum || length > maximum || invalidControl) {
    throw FormatException('$name is invalid');
  }
}

void _recordWindow(DateTime createdAt, DateTime expiresAt, DateTime now) {
  if (createdAt.isAfter(now.add(const Duration(seconds: 5))) ||
      !expiresAt.isAfter(now) ||
      !expiresAt.isAfter(createdAt) ||
      expiresAt.difference(createdAt) > const Duration(minutes: 10)) {
    throw const FormatException(
      'P2P JSON record timestamps are expired or out of order',
    );
  }
}
