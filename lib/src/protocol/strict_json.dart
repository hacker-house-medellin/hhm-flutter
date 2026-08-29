import 'dart:convert';
import 'dart:typed_data';

/// Decodes a bounded UTF-8 JSON object while rejecting duplicate object keys.
///
/// `jsonDecode` otherwise keeps the last duplicate, which is unsafe for signed
/// or policy-bearing protocol documents because different implementations may
/// verify and act on different values.
Map<String, Object?> decodeStrictJsonObject(
  Uint8List bytes, {
  required int maximumBytes,
}) {
  if (bytes.isEmpty || bytes.length > maximumBytes) {
    throw const FormatException('JSON document size is invalid');
  }
  late final String source;
  try {
    source = utf8.decode(bytes, allowMalformed: false);
    _DuplicateKeyScanner(source).scanDocument();
  } on FormatException {
    rethrow;
  } on Object {
    throw const FormatException('Document is not strict UTF-8 JSON');
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(source);
  } on Object {
    throw const FormatException('Document is not valid JSON');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Document must be a JSON object');
  }
  return decoded;
}

final class _DuplicateKeyScanner {
  _DuplicateKeyScanner(this.source);

  final String source;
  int _offset = 0;

  void scanDocument() {
    _whitespace();
    _value();
    _whitespace();
    if (_offset != source.length) {
      throw const FormatException('Trailing JSON content');
    }
  }

  void _value() {
    _whitespace();
    if (_offset >= source.length) {
      throw const FormatException('Unexpected end of JSON');
    }
    switch (source.codeUnitAt(_offset)) {
      case 0x7b: // {
        _object();
      case 0x5b: // [
        _array();
      case 0x22: // "
        _string();
      case 0x74: // t
        _literal('true');
      case 0x66: // f
        _literal('false');
      case 0x6e: // n
        _literal('null');
      default:
        _number();
    }
  }

  void _object() {
    _expect(0x7b);
    _whitespace();
    if (_consume(0x7d)) return;
    final keys = <String>{};
    while (true) {
      _whitespace();
      final key = _string();
      if (!keys.add(key)) {
        throw FormatException('Duplicate JSON object key: $key');
      }
      _whitespace();
      _expect(0x3a);
      _value();
      _whitespace();
      if (_consume(0x7d)) return;
      _expect(0x2c);
    }
  }

  void _array() {
    _expect(0x5b);
    _whitespace();
    if (_consume(0x5d)) return;
    while (true) {
      _value();
      _whitespace();
      if (_consume(0x5d)) return;
      _expect(0x2c);
    }
  }

  String _string() {
    final start = _offset;
    _expect(0x22);
    while (_offset < source.length) {
      final code = source.codeUnitAt(_offset++);
      if (code == 0x22) {
        final token = source.substring(start, _offset);
        final decoded = jsonDecode(token);
        if (decoded is! String) {
          throw const FormatException('Invalid JSON string');
        }
        return decoded;
      }
      if (code < 0x20) {
        throw const FormatException('Unescaped JSON control character');
      }
      if (code == 0x5c) {
        if (_offset >= source.length) {
          throw const FormatException('Incomplete JSON escape');
        }
        final escape = source.codeUnitAt(_offset++);
        if (escape == 0x75) {
          if (_offset + 4 > source.length) {
            throw const FormatException('Incomplete Unicode escape');
          }
          for (var index = 0; index < 4; index++) {
            final hex = source.codeUnitAt(_offset++);
            final valid =
                (hex >= 0x30 && hex <= 0x39) ||
                (hex >= 0x41 && hex <= 0x46) ||
                (hex >= 0x61 && hex <= 0x66);
            if (!valid) {
              throw const FormatException('Invalid Unicode escape');
            }
          }
        } else if (!const <int>{
          0x22,
          0x5c,
          0x2f,
          0x62,
          0x66,
          0x6e,
          0x72,
          0x74,
        }.contains(escape)) {
          throw const FormatException('Invalid JSON escape');
        }
      }
    }
    throw const FormatException('Unterminated JSON string');
  }

  void _number() {
    final start = _offset;
    while (_offset < source.length &&
        !const <int>{
          0x20,
          0x09,
          0x0a,
          0x0d,
          0x2c,
          0x5d,
          0x7d,
        }.contains(source.codeUnitAt(_offset))) {
      _offset++;
    }
    if (_offset == start) {
      throw const FormatException('Invalid JSON value');
    }
    final token = source.substring(start, _offset);
    final decoded = jsonDecode(token);
    if (decoded is! num) {
      throw const FormatException('Invalid JSON number');
    }
  }

  void _literal(String literal) {
    if (!source.startsWith(literal, _offset)) {
      throw const FormatException('Invalid JSON literal');
    }
    _offset += literal.length;
  }

  void _whitespace() {
    while (_offset < source.length &&
        const <int>{
          0x20,
          0x09,
          0x0a,
          0x0d,
        }.contains(source.codeUnitAt(_offset))) {
      _offset++;
    }
  }

  bool _consume(int code) {
    if (_offset < source.length && source.codeUnitAt(_offset) == code) {
      _offset++;
      return true;
    }
    return false;
  }

  void _expect(int code) {
    if (!_consume(code)) {
      throw const FormatException('Invalid JSON structure');
    }
  }
}
