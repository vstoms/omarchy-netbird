# NetBird for Omarchy

A native [Omarchy](https://omarchy.org/) bar plugin for [NetBird](https://netbird.io/).

> Community project. Not affiliated with or endorsed by NetBird GmbH.

## Features

- NetBird connection state in the bar
- Connect/disconnect from the panel or with a right click
- NetBird IP, profile, management, and signal status
- Connected and disconnected peer list
- Copy peer IP addresses or names
- Open SSH and ping sessions in the configured Omarchy terminal
- Open the NetBird admin console
- Mouse and keyboard friendly

## Requirements

- A recent Omarchy release with shell plugin support
- `netbird` installed, configured, and available on `PATH`
- `wl-copy` for clipboard actions (included with Omarchy)

Authenticate NetBird once before using the plugin:

```bash
netbird up
```

## Install

```bash
omarchy plugin add https://github.com/vstoms/omarchy-netbird.git --enable
```

The widget defaults to the right side of the bar. Move it if desired:

```bash
omarchy bar move vstoms.netbird --section right
```

Update later with:

```bash
omarchy plugin update vstoms.netbird
```

## Usage

### Mouse

- **Left click bar icon:** open/close the panel
- **Right click bar icon:** connect/disconnect
- **Middle click bar icon:** refresh
- **Click peer row:** copy its NetBird IP
- Peer action buttons: copy IP, SSH, or ping

### Keyboard

With the panel open:

- `j` / `k` or arrows: move
- `enter` / `space`: toggle NetBird or copy the selected peer IP
- `c`: copy selected peer IP
- `n`: copy selected peer name
- `s`: SSH to selected peer
- `p`: ping selected peer
- `t`: connect/disconnect
- `r`: refresh
- `a`: open admin console
- `esc`: close

## Settings

Use Omarchy's bar settings to configure:

- Refresh interval (5–3600 seconds)
- Whether disconnected peers are shown
- Admin console URL

## IPC

```bash
omarchy-shell vstoms.netbird status
omarchy-shell vstoms.netbird refresh
omarchy-shell vstoms.netbird up
omarchy-shell vstoms.netbird down
omarchy-shell vstoms.netbird toggleNetbird
```

## Credits

Inspired by Dadangdut33's [NetbirdStatus plugin for DMS](https://github.com/Dadangdut33/dms-plugins/tree/master/NetbirdStatus), itself ported from the Noctalia NetBird plugin. This implementation is written for Omarchy's native plugin API.

NetBird and its logo are trademarks of NetBird GmbH.

## License

MIT — see [LICENSE](LICENSE).
