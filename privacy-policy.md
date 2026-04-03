# Privacy Policy — ZX Tape Player

**Last updated:** April 3, 2026

## Overview

ZX Tape Player is a virtual cassette player for ZX Spectrum. This policy describes how the application handles user data.

## Data Collection

ZX Tape Player **does not collect, store, or transmit** any personal data. The application:

- Does not require user registration or login
- Does not use analytics or tracking services
- Does not use advertising SDKs or advertising identifiers
- Does not collect device identifiers, location, or usage statistics

## Network Access

The application connects to the following external services solely to provide its core functionality:

- **ZXInfo API** (`api.zxinfo.dk`) — to search and retrieve metadata about ZX Spectrum software
- **ZXInfo Media** (`zxinfo.dk/media`) — to display screenshots
- **Archive.org** and other public sources — to download tape files

These requests are made on behalf of the user and no personal information is sent beyond what is required by the HTTP protocol (e.g., IP address).

## Local Files

When you open local tape files (TAP, TZX, ZIP), they are converted to audio entirely on your device. The file contents are not uploaded to any server. However, a SHA512 hash of the file may be sent to the ZXInfo API to identify the software and retrieve its metadata.

## Third-Party Services

The application does not integrate any third-party services that collect user data (e.g., Firebase, Google Analytics, Facebook SDK).

## Children's Privacy

The application does not knowingly collect any personal information from children.

## Changes to This Policy

Any updates to this policy will be reflected in this document with an updated date.

## Contact

If you have questions about this privacy policy, please open an issue in the project's GitHub repository.
