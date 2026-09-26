# Changelog

## 1.1.0

### Added

- preset selector with EUI Default, Compact, and Dense built in
- up to 10 named custom presets
- save, update, rename, and delete controls for custom presets
- separate horizontal and vertical spacing controls
- wider layout ranges: 18-50 px slots, 6-30 columns, 0-12 px spacing, and 50-150% scale ranges
- 1% steps for bank scale

### Fixed

- bank refreshes briefly snapping toward EllesmereUI's default layout
- later rows in large OneBank / OneWarband views sometimes using the default slot size
- custom slot sizing while EllesmereUI finishes rendering large bank views
- preset name field visibility and preset-section alignment

### Changed

- existing 1.0.0 spacing is migrated to both horizontal and vertical spacing

## 1.0.0

First public release.

- configurable slot size, columns, and spacing
- separate bank scale
- item text scale
- Warband-only option
- Compact, Dense, and EUI Default presets
- `/ebt` settings command
