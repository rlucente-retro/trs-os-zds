# TRS-OS macOS Build Automation

This repository provides build automation to compile Daniel Paul Martin's **TRS-OS** (TRSDOS 6.3.1 / LS-DOS 6.3 for the Zilog eZ80) directly from the macOS terminal (Apple Silicon and Intel) without requiring an interactive Windows installation.

It includes an automated patchset specifically tailored for the **Olimex Agon Light 2** when paired with the **Olimex MOD-WIFI-ESP8266** module via its 10-pin **UEXT** expansion connector, enabling transparent TCP/IP network disk streaming with [`trs-netd`](https://github.com/rlucente-retro/trs-net-tcp).

The built operating system binary (`TRSDOS.bin`) is launched on the Agon Light using Shawn Sijnstra's [**OSboot** loader](https://github.com/sijnstra/agon-projects/tree/main/OSboot).

---

## What This Repository Does

* **Automated Downloads**: Fetches the official upstream TRS-OS source tree (`TRSDOS_7.zip`) and Zilog ZDS II development tools directly from upstream distribution points.
* **Automated Patchset Pipeline**: Applies architecture-specific patches (`patches/`) after fetch to adapt upstream TRS-OS for the Olimex Agon Light 2 hardware environment.
* **Headless macOS Build Pipeline**: Assembles and links `TRSDOS.hex` using Zilog's command-line tools (`ez80asm.exe` and `eZ80link.exe`) through Apple's 32-on-64 WoW64 Wine translation layer (`wine64`).
* **Binary Generation for OSboot**: Converts the assembled Intel HEX binary directly into a flat binary (`TRSDOS.bin`) ready to be deployed with `OSboot`.
* **Source Integrity**: Upstream source archives and unpacked trees are kept separate and gitignored; only the patchset and build automation are version-controlled.

---

## Target Hardware: Olimex Agon Light 2 with MOD-WIFI-ESP8266 on UEXT

The included patchset ([`patches/0001-uart1-streaming.patch`](patches/0001-uart1-streaming.patch)) is designed specifically for:

* **Host Computer**: **Olimex Agon Light 2** (Zilog eZ80F92 microcontroller running at 18.432 MHz).
* **Expansion Header**: **10-pin UEXT connector** (standard Olimex peripheral interface).
* **Wireless Module**: **Olimex MOD-WIFI-ESP8266** (plugged directly into UEXT, running factory Espressif ESP-AT firmware).
* **Bootstrap Loader**: **`OSboot.bin`** ([sijnstra/agon-projects/OSboot](https://github.com/sijnstra/agon-projects/tree/main/OSboot)) executed from Quark MOS.
* **Networking Daemon**: Connected over Wi-Fi to a host running **`trs-netd`** (TRS-NET TCP/IP daemon) in transparent streaming mode (`CIPMODE=1`).

```
+------------------------------------+          +-----------------------+
|        Olimex Agon Light 2         |          | Olimex MOD-WIFI-ESP8266|
|           (Zilog eZ80F92)          |          |       (ESP8266)       |
|                                    |   UEXT   |                       |
|  PC0 (TXD1) [Pin 3] -------------->|--------->| RXD (GPIO3)           |
|  PC1 (RXD1) [Pin 4] <--------------|<---------| TXD (GPIO1)           |
|  3.3V Power [Pin 1] -------------->|--------->| 3.3V VCC              |
|  Ground     [Pin 2] -------------->|--------->| GND                   |
|                                    |          |                       |
|  * NO RTS / CTS on UEXT connector *|          | Factory ESP-AT Firmware|
+------------------------------------+          +-----------+-----------+
                                                            |  Wi-Fi (TCP)
                                                            v
                                                  +-------------------+
                                                  |    trs-netd       |
                                                  | (TRS-NET Server)  |
                                                  +-------------------+
```

### Why These Specific Changes Are Necessary

1. **Absence of Hardware Flow Control (No RTS/CTS on UEXT):**
   * The Olimex UEXT expansion header routes only 3.3V, GND, I2C, SPI, and UART1 (`TXD1` on Pin 3 / `PC0` and `RXD1` on Pin 4 / `PC1`). **Hardware RTS and CTS lines are not wired to UEXT.**
   * *Upstream Behavior:* The original TRS-OS driver (`driver-UART1.S`) polled the CTS status bit (`UART1.tst.cts`) in `TXUART1` before transmitting every character, causing all network transmissions to stall indefinitely on the Agon Light 2. It also toggled RTS (`UART1.rts.set` / `UART1.rts.reset`) in `RXUART1` on every received byte.
   * *Patch Fix:* Removes `UART1.tst.cts` from `TXUART1` (transmissions only poll the transmitter holding register empty flag `THRE`) and removes per-byte RTS toggling from `RXUART1`.

2. **115,200 Baud Rate & 18.432 MHz Clock Math:**
   * The Olimex MOD-WIFI-ESP8266 communicates at **115,200 baud** by default.
   * The Agon Light 2 operates with an **18.432 MHz** crystal oscillator.
   * The eZ80 Baud Rate Generator (BRG) divisor formula yields an exact integer with 0% error:
     $$\text{Divisor} = \frac{18,432,000}{16 \times 115,200} = 10 \quad (\text{0x000A})$$
   * *Upstream Behavior:* Upstream equates assumed 230,400 baud and 20 MHz / 50 MHz dev-kit clocks, which yielded invalid divisor values on the Agon Light 2.
   * *Patch Fix:* Updates `DEVICE.serialnet.baud EQU 115200` and calculates divisors against `18432000`.

3. **Agon MOS Boot Handover via OSboot & Port C GPIO Multiplexing:**
   * When Quark MOS launches TRS-OS via `OSboot.bin`, it identifies the Agon platform by passing `UART0_SPR = 3`.
   * *Upstream Behavior:* Upstream TRS-OS jumped to `NOINITIAL` / `finish_init`, bypassing all CPU peripheral and UART1 initialization routines.
   * *Hardware Conformance on eZ80F92:* Unlike the eZ80F91 (where UART1 is on Port D), the eZ80F92 multiplexes UART1 on **Port C** (`PC0`=TXD1, `PC1`=RXD1).
   * *Patch Fix:* Configures Port C Mode 7 (Alternate Function: `PC_DDR`=1, `PC_ALT1`=0, `PC_ALT2`=1 for bits 0 and 1), loads the BRG divisor (10), executes a brief stabilization warmup (`LD B,0; DJNZ $`), and enables the 16-byte hardware FIFOs during `finish_init`.

4. **FIFO Management & Interrupt Masking for TCP Streaming:**
   * In transparent streaming mode (`CIPMODE=1`), the ESP8266 outputs 260-byte sector payloads (256-byte sector + 4-byte checksum) back-to-back at 115,200 baud (~86.8 µs/byte).
   * *Patch Fix:* Flushes the UART1 16-byte RX/TX FIFOs (`out0 (UART1_FCTL), 07h`) before issuing read/write requests to clear any lingering AT command tokens, and masks interrupts (`DI` / `EI`) during multi-byte streaming reads in IPL routines to prevent the 60 Hz timer tasker from overrunning the 16-byte receive FIFO.

5. **Network Latency Tolerance:**
   * Increases the timeout counter (`echo_delay_ct`) in `driver-UART1.S` from 25 to 60 (~3.4 seconds) to accommodate Wi-Fi packetization intervals and TCP round-trip delays without timing out.

6. **Explicit UART1 Interrupt Masking (Prevent STRAY.handler Freezes):**
   * Upstream TRS-OS routes all peripheral interrupts except TIMER1 directly to `STRAY.handler` (`jr $`, CPU freeze).
   * If Quark MOS or prior code leaves interrupt enable bits set in `UART1_IER`, incoming Wi-Fi characters or empty transmitter buffers trigger unhandled interrupts and lock up the CPU.
   * *Patch Fix:* Explicitly zeroes `UART1_IER` (`XOR A; OUT0 (UART1_IER), A`) during `finish_init` while DLAB is disabled, enforcing pure polled I/O operation.

7. **Stack Balance Fix in Ping Verification:**
   * *Upstream Behavior:* In `ipl_net_ping.s`, `no_pong` unconditionally popped 2 bytes (`pop hl`) off the stack, assuming it was called via `IF_NE_GOSUB`. However, when `CMP.bytes` encountered a buffer mismatch, it jumped to `no_pong` via `IF_NE_GOTO` (`jp nz`) without pushing a call address. This caused `pop hl` to pop the caller's return address, corrupting the stack and crashing upon return.
   * *Patch Fix:* Isolates `ping_timeout` (which pops the call address before jumping to `no_pong`) from `no_pong` (which re-enables interrupts without modifying the stack), matching the verified pattern in `ipl_net_bind.s`.

8. **Stack Preservation and Error Recovery in Network Disk Driver (driver-FDCDVR.S):**
   * *Read Retry Stack Corruption:* In `RDIN`, after receiving a sector, upstream popped the buffer address (`pop hl`) without pushing it back before `calc_cksum`. If a checksum error occurred, the subsequent retry popped `DE` (track/sector) instead of the buffer, shifting stack frames on every retry and corrupting memory. The patch keeps the buffer address on the stack (`pop hl; push hl`), popping and discarding it only upon successful checksum verification before `rd_finish`.
   * *Timeout vs. Retry Stack Isolation:* `UART1.get.bytes` and `UART1.put.bytes` invoke `IF_NE_GOSUB` (`call nz`), pushing a 2-byte return address on timeout, whereas retry counter exhaustion jumps via `IF_EQ_GOTO` (`jp z`) without pushing a call address. Upstream `fdc_rd_err` and `fdc_wr_err` failed to account for this difference, popping incorrect stack items and jumping to invalid return addresses. The patch introduces dedicated timeout vectors (`fdc_rd_timeout`, `fdc_wr_timeout`, `fdc_wr_timeout1`) that pop the call return address (and saved checksum in write) before merging into `fdc_rd_err` / `fdc_wr_err`, which cleanly restore `DE`, `BC`, and `HL` before returning.

---

## Booting TRS-OS with OSboot on Agon Light

Shawn Sijnstra's [**OSboot**](https://github.com/sijnstra/agon-projects/tree/main/OSboot) tool is the standard MOS bootstrap loader for launching TRS-OS natively on the Agon Light family.

### MicroSD Card Deployment

1. Download [`OSboot.bin`](https://github.com/sijnstra/agon-projects/raw/main/OSboot/OSboot.bin) and place it in the `/mos` directory of your Agon microSD card so MOS can execute it as a command.
2. Copy `TRSDOS.bin` (built by `make`) to the root of the microSD card.
3. *(Optional)* Download `TRS80M4pG.F10` (authentic 8×10 TRS-80 Model 4 font) and place it on the SD card.

### Launching from Quark MOS

At the MOS prompt (`*`), invoke `OSboot`:

```text
OSboot [-Xvf] TRSDOS.bin [diskfile]
```

#### Command Options:
* `-X`: Sets the terminal text color, where `X` is from `1` to `7`:
  * `-1`: Red, `-2`: Green (default), `-3`: Yellow, `-4`: Blue, `-5`: Magenta, `-6`: Cyan, `-7`: White.
* `-v`: Forces VT100 terminal mode instead of ADDS25 (default).
* `-f`: Loads font 1 into terminal mode (requires VDP 2.11.0+ with `loadfont 1 TRS80M4pG.F10` loaded in `autoexec.txt`).
* `[diskfile]`: Optional path to a JV1 or DiskDISK format virtual disk image (up to 200 KB) to mount as Drive `:1`.

**Example:**
```text
*OSboot -2f TRSDOS.bin
```

---

## Operating Workflow: Connecting to trs-netd via MOS Streaming Mode

The patched TRS-OS operates cleanly within the intended streaming lifecycle without breaking or interfering with the transparent TCP stream:

```
[ Quark MOS ]                                                  [ Host Server ]
  |
  +--> openstream <ip> <port> ------------------------------> trs-netd.py
  |    (ESP8266 enters CIPMODE=1 streaming mode)                (TCP connected)
  |
  +--> OSboot -2f TRSDOS.bin
  |    (Hands execution to TRS-OS via UART0_SPR = 3)
  v
[ TRS-OS ]
  |
  +--> finish_init: preserves Mode 7 & BRG (115200), flushes FIFOs
  +--> ipl-BIOS: sends @ping \n ----------------------------> receives @pong \n
  +--> IPL Menu ('n' -> 'b'): sends @bind \n --------------> receives @bound \n + header
  +--> Floppy Driver (:6): reads ('<') / writes ('>') -----> streams sectors & checksums
  v
[ Hardware Reset Button Pressed ]
  | (eZ80 resets into MOS; ESP8266 on UEXT remains powered and streaming)
  v
[ Quark MOS ]
  |
  +--> closestream -----------------------------------------> closes TCP session
       (Sends '+++' with guard silence, then AT+CIPCLOSE)       (Client disconnected)
```

### Step-by-Step Procedure:

1. **Start the Network Daemon on Host PC**:
   ```bash
   python3 /path/to/trs-netd.py -v -p 8080 -d 0 /path/to/network_disk.dsk
   ```

2. **In Quark MOS (Agon Light 2)**:
   * *(Optional)* Verify host reachability:
     ```text
     *ping 192.168.1.100
     ```
   * Open transparent TCP stream to `trs-netd.py`:
     ```text
     *openstream 192.168.1.100 8080
     ```
   * Boot TRS-OS:
     ```text
     *OSboot -2f TRSDOS.bin
     ```

3. **In TRS-OS**:
   * TRS-OS initializes the video console and performs transparent UART1 FIFO synchronization.
   * At the startup splash, TRS-OS pings the server (`@ping`) and confirms `Reply received.` (`@pong`).
   * From the main IPL menu, press `n` (Network Utilities), then `b` (Bind volume). The server binds volume 0 to Drive `:6` (`@bound` + 256-byte header).
   * Press `Enter`, then `ESC` to return to the menu, and press `0` to enter TRSDOS command prompt.
   * Access Drive `:6` transparently (e.g. `DIR :6`). Sector requests (`<XXXXX` / `>XXXXX`) and checksum verification stream seamlessly over TCP.

4. **Tearing Down the Session**:
   * Press the physical **RESET** button on the Olimex Agon Light 2.
   * The eZ80 restarts into Quark MOS. The MOD-WIFI-ESP8266 module on UEXT has no hardware reset line connected and remains powered and connected in streaming mode.
   * At the MOS `*` prompt, issue `closestream`:
     ```text
     *closestream
     ```
   * `closestream` issues the required `+++` escape sequence (with 1.0s guard times) to return the ESP8266 to command mode, then sends `AT+CIPCLOSE` to shut down the TCP socket cleanly.

---

## Prerequisites

Install the required tools via Homebrew:

```bash
# Intel HEX to binary converter
brew install hex2bin

# Game Porting Toolkit Wine package for running ZDS II
brew tap gcenx/wine
brew install gcenx/wine/game-porting-toolkit
brew install winetricks
```

---

## Usage

```bash
# Fetch upstream source, apply Agon Light 2 patchset, install ZDS II (if needed),
# and build TRSDOS.hex and TRSDOS.bin
make

# Verify built binary against upstream reference image
make verify

# Clean build artifacts (leaves patched sources intact)
make clean

# Complete reset: removes downloaded sources, archives, and PDFs (leaves Makefile, README.md, patches/)
make distclean
```

### Make Targets

| Target | Description |
| :--- | :--- |
| `make` / `make all` | Default. Downloads sources/tools, applies `patches/*.patch`, builds `TRSDOS_7/TRSDOS.hex`, and generates `TRSDOS_7/TRSDOS.bin` for `OSboot`. |
| `make patch` | Applies the patchset from `patches/` to the unpacked source tree (stamped via `TRSDOS_7/.patched`). |
| `make verify` | Compiles the system and compares `TRSDOS.hex` against the upstream reference `debug/TRSDOS.hex`. |
| `make fetch` | Downloads and unpacks `TRSDOS_7.zip` from Daniel Paul Martin's site. |
| `make fetch-zds` | Downloads the ZDS II installer archive from Zilog. |
| `make install-zds` | Silently installs ZDS II into `~/.wine/drive_c/Zilog/` using `wine64`. |
| `make clean` | Removes object files, listing files, maps, and generated binaries (`.hex` and `.bin`). |
| `make distclean` | Removes all downloaded source archives, unpacked directories, and PDFs. |

---

## Attributions & Third-Party Credits

* **TRS-OS**: Created and maintained by **Daniel Paul Martin**. Port of TRSDOS / LS-DOS 6.3 to the Zilog eZ80 platform. Project details and original archives are available at [danielpaulmartin.com](https://danielpaulmartin.com/home/research/).
* **OSboot**: Agon bootstrap loader created and maintained by **Shawn Sijnstra** ([sijnstra/agon-projects](https://github.com/sijnstra/agon-projects/tree/main/OSboot)).
* **Agon Light Hardware Platform**: Designed by Bernardo Kastrup ([The Byte Attic](https://www.thebyteattic.com/p/agon.html)) and manufactured as the AgonLight2 by [OLIMEX](https://www.olimex.com/Products/Retro-Computers/AgonLight2/).
* **MOD-WIFI-ESP8266**: Hardware expansion module designed and manufactured by [OLIMEX](https://www.olimex.com/Products/Modules/WiFi/MOD-WIFI-ESP8266/).
* **ZDS II & eZ80**: **ZDS II - eZ80Acclaim!** software and the **eZ80** processor architecture are proprietary technologies and registered trademarks of **Zilog, Inc.** (a Littelfuse company).
