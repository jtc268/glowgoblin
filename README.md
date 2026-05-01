# RollHDR

RollHDR is a tiny hidden macOS app that lets MacBook Pro Liquid Retina XDR displays keep rolling past normal SDR brightness.

It has no Dock icon, no menu bar item, and no settings. Install it once, log in, and use the regular keyboard brightness keys. When you push brightness up, it lands in the extra-bright XDR range. When you play real HDR content, including YouTube HDR videos, macOS still handles HDR playback normally.

Built by PingPong for friends who want the screen brighter without a control panel.

## Why

Apple's XDR panels can get much brighter than the normal SDR desktop limit, but macOS only exposes that headroom to HDR/EDR content. RollHDR keeps an invisible EDR layer alive and applies a display gamma lift only on supported built-in XDR displays.

The important bit: brightness-key transitions are where flicker usually happens. RollHDR backs off while Apple's hardware brightness stack is actively moving, then restores the full boost after the panel settles. The result is bright at rest without fighting the display during adjustment.

## Install

Requirements:

- MacBook Pro with a Liquid Retina XDR display
- macOS 13 or newer
- Xcode Command Line Tools

Fast path:

```sh
curl -fsSL https://raw.githubusercontent.com/jtc268/rollhdr/main/Scripts/bootstrap.sh | bash
```

Manual path:

```sh
git clone https://github.com/jtc268/rollhdr.git
cd rollhdr
./Scripts/install.sh
```

The app installs to:

```sh
~/Applications/RollHDR.app
```

The startup agent installs to:

```sh
~/Library/LaunchAgents/app.pingpong.rollhdr.plist
```

## Use

Press the normal Mac brightness keys. There is no UI.

For color-critical work, disable RollHDR and use Apple's reference modes. RollHDR is for practical brightness, not reference grading. It intentionally pushes SDR desktop brightness beyond Apple's normal SDR behavior, so games and SDR apps can look different.

## Status

```sh
./Scripts/status.sh
```

## Uninstall

```sh
./Scripts/uninstall.sh
```

Uninstall stops the agent, removes the app, and restores ColorSync display tables.

## Notes

- Only built-in Apple XDR/EDR-capable displays are targeted.
- External displays are left alone unless macOS reports them as Apple XDR-like.
- Real HDR video playback still works; RollHDR is not an HDR player or tone mapper.
- This uses private-ish display behavior exposed through public macOS APIs. If Apple changes the display stack, behavior may change.

## Credits

RollHDR was informed by the public macOS XDR brightness experiments around BrightIntosh and BrightXDR, then tuned around transition flicker on a real MacBook Pro.

MIT licensed.
