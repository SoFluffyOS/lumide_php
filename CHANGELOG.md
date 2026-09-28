# Changelog

All notable changes to the `lumide_php` plugin will be documented in this file.

## [Unreleased]

### Added
- Register every installed PHP server independently; manage each in Lumide’s LSP & Agents panel.
- Discover new servers without duplicating registrations.
- Map PHP and Blade files to the `php` language ID with SDK 1.11.0.

### Changed
- `php.lsp.server` sets registration order; all discovered servers remain available.
- Custom servers coexist with built-ins; duplicate commands register once.
- Replace switch/restart actions with discovery/status; keep command IDs for keybindings.
- Show registered servers in the status tooltip and send licence keys only to Intelephense.

## [1.0.0] - 2026-08-18

### Added
- Initial release of Lumide PHP plugin.
- Dynamic LSP integration supporting Intelephense, Phpactor, and PHP Language Server.
- Switch and restart LSP server commands.
- Full Composer tooling (install, update, dump-autoload, validate, require, run-script).
- PHP built-in web server manager with status bar indicator and browser launcher.
- Test runner supporting Pest and PHPUnit.
- Linting via `php -l` and code formatting via Laravel Pint / PHP-CS-Fixer.
- Context menu contributions for PHP files and `composer.json`.
