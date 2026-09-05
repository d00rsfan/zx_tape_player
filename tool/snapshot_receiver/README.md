# Snapshot receiver asset revision

The bundled receiver assets are based on ZQLoader commit
`a6fdb6a889f0ca4a928c37d030527b577a941793` plus
`zqloader-a6fdb6a-correctness.patch` in this directory.

The patch changes the wire header from 17 to 18 bytes by adding a check byte
whose add/rotate checksum residue is zero. The receiver validates that residue
before it uses the payload length, addresses, compression type, or action. It
also records when `COPY_ME` has replaced the BASIC stack and uses stable border
colours for fatal errors after that point instead of printing or returning
through overwritten RAM:

- red (2): payload checksum failure;
- magenta (3): timeout or invalid header;
- yellow (6): an invalid request to return to BASIC after relocation.

## Rebuild

Apply the patch to a clean checkout at the commit above, then run from its
`z80` directory:

```sh
/usr/local/bin/sjasmplus --fullpath \
  -i/home/lena/pets/sjasmplus/examples/BasicLib \
  --exp=zqloader48.exp --lst --syntax=abf zqloader48.z80asm
/usr/local/bin/sjasmplus --fullpath \
  -i/home/lena/pets/sjasmplus/examples/BasicLib \
  --exp=zqloader128.exp --lst --syntax=abf zqloader128.z80asm
```

Copy `zqloader48.tap`, `zqloader128.tap`, and `snapshotregs.bin` to
`assets/snapshots/`, then update the manifest only if the following inspected
symbols and hashes intentionally changed. The current build uses sjasmplus
1.24.0 and produces:

```text
80d5fee750bad222526468bf6df3f54a36182fb9b1335aced70ec849a439ccf5  zqloader48.tap
32a2bbfc10e8c3139736f88d72b5031dde3ba7205768fd9c6e71ba8e7dd57f34  zqloader128.tap
a31fde91bc259ac4fdd3d442627f8495b98a9bae66644f1eb7b1414a181ad96f  snapshotregs.bin
```

The app build does not invoke sjasmplus; generated assets and their symbol
contract remain integrity-pinned in `SnapshotReceiverManifest`.
