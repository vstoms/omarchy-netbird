# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.1] - 2026-08-15

### Changed

- Added the panel preview to the README so the plugin UI is visible before
  installation.
- Clarified that pre-authentication is optional because the panel provides a
  guided NetBird login flow.

### Fixed

- Treat `Connecting` as active even when the transition starts outside the
  plugin, and clear optimistic switch state when a connection attempt stops or
  the daemon becomes unreachable.
- Distinguish user-cancelled and timed-out login processes from authentication
  failures, while reporting failures that happen after the verification URL is
  shown.
- Bound network selection commands with a timeout so a lost daemon cannot
  leave them running indefinitely.
- Prevent the `w` shortcut from toggling a network unless the keyboard cursor
  is in the networks section.
- Keep connecting peers visible when disconnected peers are hidden.
- Clear stale CLI/daemon version mismatch warnings when status is cleared.
- Serialize network listing and selection changes so an in-flight list cannot
  overwrite a newly applied selection with stale data.

## [2.0.0] - 2026-08-15

### Added

- Networks section: select and deselect NetBird networks and resources from the
  panel, with select-all and deselect-all, mirroring `netbird networks list`.
- Relay status: availability count in the panel, expandable per-relay list with
  the error for any relay that is unreachable.
- Connection lifecycle states. `Idle`, `Connecting`, `Connected`, `NeedsLogin`,
  `LoginFailed`, and `SessionExpired` are now distinguished instead of being
  collapsed into "Disconnected", each with its own explanation.
- Guided SSO login. Turning NetBird on while it needs credentials runs
  `netbird up --no-browser`, opens the verification URL in the Omarchy browser,
  and shows the user code in the panel.
- Daemon-down handling, with the service start command and a retry action.
- Peer search (`/`) over names, FQDNs, IP addresses, connection types, and
  advertised subnets.
- Peer detail (`d`), showing why a peer is relayed or direct, the ICE candidate
  pair, endpoints, handshake age, transferred bytes, routed subnets, and
  quantum resistance, plus copy actions for the name and public key.
- Connecting peers are shown as a distinct state rather than as offline.
- Version mismatch warning when the NetBird CLI and daemon report different
  versions.
- Bar icon tooltip reporting connection state and peer counts.
- Bar icon turns urgent when NetBird is connected but management, signal, or
  relays are unhealthy.
- Settings: `showNetworks`, `monochromeIcon`.
- IPC: `state`, `login`, `relays`, `networks`, `selectNetwork`,
  `deselectNetwork`.

### Changed

- **The bar icon is now monochrome by default**, drawn as vector paths and
  painted in the bar's foreground colour like other Omarchy bar icons. Set
  `monochromeIcon` to `false` for the NetBird brand colours.
- Status polling backs off exponentially, up to five minutes, while the daemon
  is unreachable.
- Peers sort connected, then connecting, then idle, then disconnected.
- The bar icon uses the bar foreground rather than the panel foreground.

### Fixed

- Status calls no longer hang. `netbird status` retries a missing daemon socket
  indefinitely rather than failing, which left a stuck process behind on every
  poll and reported "NetBird status timed out". Calls are now bounded with
  `timeout` and classified as a daemon-down state.
- A daemon reporting `Connecting` is no longer displayed as connected when the
  management connection happens to be up.
- Peers whose status is `Connecting` are no longer rendered as disconnected.

## 1.0.0 - 2026-08-14

### Added

- Initial release: NetBird connection state in the bar, connect and disconnect,
  connection details, peer list with copy, SSH, and ping actions, admin console
  shortcut, keyboard navigation, and IPC commands.

[2.0.1]: https://github.com/vstoms/omarchy-netbird/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/vstoms/omarchy-netbird/releases/tag/v2.0.0
