# EllesmereUI for Wrath of the Lich King

An in-progress port of EllesmereUI for World of Warcraft: Wrath of the Lich King
3.3.5a. It is experimental and not yet ready for general use.

## Installation

1. Clone or copy this repository into your WoW `Interface/AddOns` directory as
   `EllesmereUI`.
2. From the `EllesmereUI` directory, run the platform-appropriate installer:
   - Windows: `install.bat`
   - macOS/Linux: `./install.sh`
3. Start the game and enable EllesmereUI and its linked modules in the AddOns
   menu.

The installers create links in the parent `AddOns` directory for each module.
This is required because the WotLK client does not load add-ons from nested
directories.

## Project layout

- `EllesmereUI.toc` and the root Lua files provide the shared framework.
- `EllesmereUI*/` directories contain feature modules such as action bars,
  bags, chat, nameplates, raid frames, and unit frames.
- `Compatibility/` contains WotLK 3.3.5a compatibility shims.
- `Locales/` contains translations.
- `Libs/` contains bundled libraries.

## Development

Contributions are welcome. Please read the
[contribution guide](.github/CONTRIBUTING.md) before opening a pull request.

## License

This project uses a custom license. See [license.txt](license.txt).
