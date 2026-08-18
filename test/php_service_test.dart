import 'package:test/test.dart';

void main() {
  group('PhpService', () {
    test('parses standard PHP CLI version string', () {
      const sampleCli = '''
PHP 8.3.4 (cli) (built: Mar 12 2024 23:42:01) (NTS)
Copyright (c) The PHP Group
Zend Engine v4.3.4, Copyright (c) Zend Technologies
    with Zend OPcache v8.3.4, Copyright (c), by Zend Technologies
''';
      final match = RegExp(r'PHP\s+([0-9]+\.[0-9]+(\.[0-9]+)?)').firstMatch(
        sampleCli.split('\n').first,
      );
      expect(match, isNotNull);
      if (match case final m?) {
        expect(m.group(1), equals('8.3.4'));
      }
    });

    test('parses minor PHP version string', () {
      const sampleCli = 'PHP 8.2 (cli)';
      final match = RegExp(r'PHP\s+([0-9]+\.[0-9]+(\.[0-9]+)?)').firstMatch(
        sampleCli,
      );
      expect(match, isNotNull);
      if (match case final m?) {
        expect(m.group(1), equals('8.2'));
      }
    });
  });
}
