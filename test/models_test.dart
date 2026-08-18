import 'package:lumide_php/lumide_php.dart';
import 'package:test/test.dart';

void main() {
  group('LspServerType', () {
    test('parses from strings correctly', () {
      expect(LspServerType.fromString('intelephense'),
          equals(LspServerType.intelephense));
      expect(LspServerType.fromString('Intelephense '),
          equals(LspServerType.intelephense));
      expect(
          LspServerType.fromString('phpactor'), equals(LspServerType.phpactor));
      expect(LspServerType.fromString('php-language-server'),
          equals(LspServerType.phpLanguageServer));
      expect(LspServerType.fromString('custom'), equals(LspServerType.custom));
      expect(LspServerType.fromString('unknown'), equals(LspServerType.auto));
      expect(LspServerType.fromString(null), equals(LspServerType.auto));
    });

    test('provides correct default command and args', () {
      expect(LspServerType.intelephense.defaultCommand, equals('intelephense'));
      expect(LspServerType.intelephense.defaultArgs, equals(['--stdio']));

      expect(LspServerType.phpactor.defaultCommand, equals('phpactor'));
      expect(LspServerType.phpactor.defaultArgs, equals(['language-server']));

      expect(LspServerType.phpLanguageServer.defaultCommand,
          equals('php-language-server'));
      expect(LspServerType.phpLanguageServer.defaultArgs, isEmpty);
    });

    test('serializes to json string ID correctly', () {
      expect(LspServerType.intelephense.toJson(), equals('intelephense'));
      expect(LspServerType.phpactor.toJson(), equals('phpactor'));
      expect(LspServerType.phpLanguageServer.toJson(),
          equals('php-language-server'));
      expect(LspServerType.custom.toJson(), equals('custom'));
      expect(LspServerType.auto.toJson(), equals('auto'));
    });
  });

  group('ComposerManifest', () {
    test('parses valid composer.json', () {
      const json = '''
      {
        "name": "vendor/project",
        "description": "A sample PHP project",
        "type": "project",
        "scripts": {
          "test": "pest",
          "lint": "pint --test"
        },
        "require": {
          "php": "^8.2",
          "symfony/yaml": "^6.0"
        },
        "require-dev": {
          "pestphp/pest": "^2.0"
        }
      }
      ''';

      final manifest = ComposerManifest.parse(json);
      expect(manifest, isNotNull);
      if (manifest case final m?) {
        expect(m.name, equals('vendor/project'));
        expect(m.description, equals('A sample PHP project'));
        expect(m.scripts.length, equals(2));
        expect(m.scripts['test'], equals('pest'));
        expect(m.hasDependency('symfony/yaml'), isTrue);
        expect(m.hasDependency('pestphp/pest'), isTrue);
        expect(m.hasDependency('laravel/framework'), isFalse);
      }
    });

    test('parses array-based composer.json scripts', () {
      const json = '''
      {
        "name": "vendor/app",
        "scripts": {
          "post-autoload-dump": [
            "@php artisan package:discover --ansi",
            "@php artisan filament:upgrade"
          ]
        }
      }
      ''';

      final manifest = ComposerManifest.parse(json);
      expect(manifest, isNotNull);
      if (manifest case final m?) {
        expect(m.scripts['post-autoload-dump'], isA<List>());
        final list = m.scripts['post-autoload-dump'] as List;
        expect(list.length, equals(2));
      }
    });

    test('returns null on invalid json', () {
      final manifest = ComposerManifest.parse('{ invalid json }');
      expect(manifest, isNull);
    });

    test('handles non-string primitives safely without throwing cast errors',
        () {
      const json = '''
      {
        "name": 12345,
        "description": true,
        "scripts": { "build": "vite build" }
      }
      ''';
      final manifest = ComposerManifest.parse(json);
      expect(manifest, isNotNull);
      expect(manifest?.name, equals('12345'));
      expect(manifest?.description, equals('true'));
      expect(manifest?.scripts['build'], equals('vite build'));
    });
  });

  group('PhpServerConfig', () {
    test('computes correct URL and supports copyWith', () {
      const config = PhpServerConfig(host: 'localhost', port: 8080);
      expect(config.url, equals('http://localhost:8080'));

      final updated = config.copyWith(port: 9000);
      expect(updated.url, equals('http://localhost:9000'));
      expect(updated.host, equals('localhost'));
    });
  });

  group('normalizeFilePath', () {
    test('converts file:// URI to standard native file path', () {
      expect(normalizeFilePath('file:///workspace/project/index.php'),
          equals('/workspace/project/index.php'));
    });

    test('returns standard file path untouched', () {
      expect(normalizeFilePath('/workspace/project/index.php'),
          equals('/workspace/project/index.php'));
    });
  });
}
