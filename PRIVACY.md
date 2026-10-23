# Bambu Bar Privacy Policy

_Last updated: October 23, 2026_

Bambu Bar is a macOS app that shows the status of Bambu Lab 3D printers on your local network. It is made by an independent developer (rolottr) and is not affiliated with Bambu Lab.

## The short version

Bambu Bar does not collect, sell or share any personal data. It has no account, no analytics, no advertising and no tracking. It talks only to the printers on your own network.

## What the app stores, and where

Everything stays on your Mac:

- **Printers you add** (name, IP address, serial number, model) and your preferences: in the app's local settings.
- **Printer access codes:** in your macOS keychain. A code is only ever sent to the printer it belongs to, over an encrypted connection that checks the printer's certificate.
- **Your last few prints** (job name, times, result), used for finish times and notifications: in a file in the app's own container.
- **A snapshot of each printer's status** for the desktop widgets: in a container shared only with Bambu Bar's widget.
- **Bambu Studio or OrcaSlicer settings:** if you choose that app's folder or settings file during setup, Bambu Bar reads the printers' access codes and addresses from it. It never changes the file, and it remembers only your permission to read it again.

Removing a printer in Settings deletes its access code from the keychain.

## Network connections

- **Your printers:** Bambu Bar connects directly to each printer on your local network (MQTT over TLS, port 8883) and listens for the announcements printers send on the network (UDP port 2021) so it can find them.
- **Nothing else:** the App Store version makes no other network requests. Copies downloaded from GitHub can check this project's GitHub releases for updates once a day; that request sends no information about you or your printers and can be turned off in Settings.

The app does not use Bambu Lab's cloud services and does not need your Bambu Lab account.

## Data collected by the developer

None. The developer receives no data from the app: no crash reports beyond what you choose to share with Apple through macOS, no usage statistics and no identifiers.

## Children

The app collects no data from anyone, including children.

## Changes

If this policy changes, the new version will be published at this address with a new date.

## Contact

Questions about privacy: open an issue at <https://github.com/rolottr/bambu-bar/issues>.
