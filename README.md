# lumide_php

[![Lumide Plugin](https://img.shields.io/badge/Lumide-Plugin-blue.svg)](https://lumide.dev)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Comprehensive **PHP language support and development tooling plugin** for [Lumide IDE](https://lumide.dev).

---

## Prerequisites

Before using the PHP plugin, make sure the following tools are installed on your system:

### 1. PHP Runtime (`>= 8.0`) — **Required**
The plugin relies on the `php` CLI binary for syntax linting (`php -l`), built-in web server (`php -S`), direct script execution, and test runners.

- **macOS** (Homebrew):
  ```bash
  brew install php
  ```
- **Ubuntu / Debian**:
  ```bash
  sudo apt update && sudo apt install php-cli php-mbstring php-xml php-curl
  ```
- **Arch Linux**:
  ```bash
  sudo pacman -S php
  ```
- **Windows**:
  - Download from [windows.php.net](https://windows.php.net/download/) (Thread Safe or Non-Thread Safe x64 ZIP) and add to `PATH`, or install via:
  ```powershell
  choco install php
  # or
  scoop install php
  ```

---

### 2. PHP Language Server (LSP) — **Recommended for Code Intelligence**
For rich IDE features such as code completions, hover documentation, parameter hints, go-to-definition, and workspace diagnostics:

- **Intelephense** *(Recommended — Fast & Full-featured)*:
  Requires [Node.js](https://nodejs.org/):
  ```bash
  npm install -g intelephense
  ```
  *(Alternatively, click **Install Intelephense (npm)** from the PHP Tools menu inside Lumide).*

- **Phpactor** *(PHP-native Language Server & Refactoring Tool)*:
  Requires PHP >= 8.2:
  ```bash
  # Install globally with Composer:
  composer global require phpactor/phpactor

  # Or install standalone PHAR directly inside Lumide:
  # Click "Install Phpactor (Standalone PHAR)" in the PHP Tools menu.
  ```

- **PHP Language Server (`felixfbecker/php-language-server`)**:
  ```bash
  composer global require felixfbecker/language-server
  ```

---

### 3. Composer — **Recommended for Project Management**
Required for dependency management, autoloading, running Composer scripts, and project-local tools:

- **macOS**: `brew install composer`
- **Linux / Windows**: Follow instructions on [getcomposer.org/download](https://getcomposer.org/download/) or:
  ```powershell
  choco install composer
  ```

---

### 4. Code Formatters & Test Runners — **Optional**
The plugin automatically discovers and runs tools installed locally in `vendor/bin/` (or from global `PATH`):

| Tool | Category | Installation Command |
|---|---|---|
| **Pest** | Test Runner | `composer require --dev pestphp/pest` |
| **PHPUnit** | Test Runner | `composer require --dev phpunit/phpunit` |
| **Laravel Pint** | Code Formatter | `composer require --dev laravel/pint` |
| **PHP-CS-Fixer** | Code Formatter | `composer require --dev friendsofphp/php-cs-fixer` |

---

## Features

### 🐘 Language Server Protocol (LSP)
Connects seamlessly with PHP Language Servers for rich IDE features (completions, parameter hints, go-to-definition, hover docs, workspace symbols, diagnostics):
- **Intelephense** (`intelephense --stdio`) — Fast, full-featured default PHP language server.
- **Phpactor** (`phpactor language-server`) — Powerful PHP-native language server and refactoring toolkit.
- **PHP Language Server** (`php-language-server`) — Pure PHP language server.
- **Custom Executable** — Use your own custom PHP language server binary or path.
- **Auto-Detection** — Automatically finds installed LSP servers in PATH.
- **Switch Engine on the Fly** (`PHP: Select Language Server`).

### 📦 Composer Integration
- `Composer: Install` — Run `composer install` in an integrated terminal.
- `Composer: Update` — Run `composer update`.
- `Composer: Dump Autoload` — Run optimized classmap generation (`composer dump-autoload -o`).
- `Composer: Validate` — Validate `composer.json` format and dependencies.
- `Composer: Require Package` — Interactively search and install PHP packages.
- `Composer: Run Script...` — Interactive quick-pick menu of all custom scripts defined in `composer.json`.
- File tree context menu integrations for `composer.json`.

### 🌐 Built-in Web Server
- `PHP: Start Built-in Web Server` — Quickly spin up `php -S <host>:<port>` without leaving Lumide.
- `PHP: Stop Built-in Web Server` — Stop the running development server.
- `PHP: Open Server in Browser` — One-click preview in default browser.
- Status bar server indicator displaying port and state.

### 🧪 Test Runner (PHPUnit & Pest)
- `PHP: Run All Tests` — Automatically detects and runs Pest or PHPUnit.
- `PHP: Run Current Test File` — Run tests specifically for the active open file.

### 🎨 Linting & Code Formatting
- `PHP: Lint Active File (php -l)` — Instant syntax checking.
- `PHP: Format Active File` — Automatically formats using Laravel Pint (`pint`) or PHP-CS-Fixer (`php-cs-fixer`).

---

## Configuration

| Setting | Type | Default | Description |
|---|---|---|---|
| `php.lsp.server` | `string` | `"auto"` | LSP engine: `auto`, `intelephense`, `phpactor`, `php-language-server`, or `custom` |
| `php.lsp.path` | `filePath` | `""` | Custom LSP executable path |
| `php.executablePath` | `filePath` | `""` | Path to `php` binary |
| `php.composer.path` | `filePath` | `""` | Path to `composer` binary |
| `php.devServer.host` | `string` | `"127.0.0.1"` | Host address for built-in web server |
| `php.devServer.port` | `number` | `8000` | Port for built-in web server |
| `php.devServer.documentRoot` | `string` | `""` | Document root folder (e.g. `public` or `web`) |
| `php.intelephense.licenceKey` | `string` | `""` | Optional premium licence key for Intelephense |

---

## Getting Started

1. Open any workspace containing PHP files (`.php`) or `composer.json` in Lumide IDE.
2. The PHP plugin activates automatically. Click the PHP logo icon in the bottom right status bar to open the **PHP Tools Menu** or switch language server engines.
