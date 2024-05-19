# Changelog

This is the list of changes to Shell Scripts between each release. For full
details, see the commit logs. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- Doas support for all Unix scripts.
- Multiple script installations with one command.

### Removed

- Function assert_cmd from all scripts.

## 0.1.2 - 2023-06-28

### Fixed

- Tscp and Tssh for Windows.

## 0.1.1 - 2023-06-23

### Fixed

- Sudo usage check for root user in POSIX scripts.

## 0.1.0 - 2023-06-21

### Added

- ClearCache, Packup, PurgeSnap, SetupTmate, Trsync, Tscp, and Tssh scripts.
