# TRS-OS macOS Build Automation

This repository provides build automation to compile Daniel Paul Martin's **TRS-OS** (TRSDOS 6.3.1 / LS-DOS 6.3 for the Zilog eZ80) directly from the macOS terminal (Apple Silicon and Intel) without an interactive Windows installation.

---

## What This Repository Does

* **Automated Downloads**: Fetches the official upstream TRS-OS source tree and Zilog ZDS II development tools directly from their respective original distribution points.
* **Headless Build Pipeline**: Assembles and links `TRSDOS.hex` using Zilog's command-line tools (`ez80asm.exe` and `eZ80link.exe`) through Apple's 32-on-64 WoW64 Wine translation layer (`wine64`).
* **Upstream Verification**: Compares the newly built binary against the author's release image to guarantee 100% bit-for-bit equivalence.

---

## Prerequisites

Install the Game Porting Toolkit Wine package via Homebrew:

```bash
brew tap gcenx/wine
brew install gcenx/wine/game-porting-toolkit
brew install winetricks
```

---

## Usage

```bash
# Fetch upstream source, install ZDS II (if needed), and build TRSDOS.hex
make

# Verify bit-for-bit match against the upstream release
make verify

# Clean build artifacts
make clean

# Reset repository back to only Makefile and README.md
make distclean
```

### Make Targets

| Target | Description |
| :--- | :--- |
| `make` / `make all` | Default. Downloads sources and tools if missing, then compiles `TRSDOS_7/TRSDOS.hex`. |
| `make verify` | Builds the system and runs `diff` against the author's official `debug/TRSDOS.hex`. |
| `make fetch` | Downloads and unpacks `TRSDOS_7.zip` from Daniel Paul Martin's site. |
| `make fetch-zds` | Downloads the ZDS II installer archive from Zilog. |
| `make install-zds` | Silently installs ZDS II into `~/.wine/drive_c/Zilog/` using `wine64`. |
| `make clean` | Removes object files, listing files, maps, and generated binaries. |
| `make distclean` | Removes all downloaded source archives, folders, and PDFs, leaving only `Makefile` and `README.md`. |

---

## Attributions & Third-Party Credits

* **TRS-OS**: Created and maintained by **Daniel Paul Martin**. Port of TRSDOS / LS-DOS 6.3 to the Zilog eZ80 platform. Project details, documentation, and original archives are available at [danielpaulmartin.com](https://danielpaulmartin.com/home/research/).
* **ZDS II & eZ80**: **ZDS II - eZ80Acclaim!** software and the **eZ80** processor architecture are proprietary technologies and registered trademarks of **Zilog, Inc.** (a Littelfuse company).
