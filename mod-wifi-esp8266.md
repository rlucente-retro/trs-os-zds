# Olimex MOD-WIFI-ESP8266 on Olimex Agon Light 2

This document describes how the **Olimex MOD-WIFI-ESP8266** module interfaces with the **Olimex Agon Light 2** retrocomputer, details its AT modem command interface, and provides an end-to-end guide for establishing and managing transparent TCP/IP communication over UART1.

---

## 1. Hardware Architecture & Pinout

The Agon Light 2 is powered by a Zilog eZ80F92 microcontroller running at 18.432 MHz. The eZ80 features two independent hardware UARTs:

* **UART0:** Dedicated internally to the onboard ESP32 Video Display Processor (VDP), handling the monitor display, audio, keyboard input, and default MOS console at 115,200 baud.
* **UART1:** Routed directly to the standard 10-pin **UEXT** expansion header.

The Olimex MOD-WIFI-ESP8266 plugs directly into this UEXT header without requiring breadboards, wiring harnesses, or logic level shifters.

### Electrical & Serial Parameters
* **Logic Level:** 3.3V TTL (both the eZ80 and ESP8266 operate natively at 3.3V).
* **Baud Rate:** 115,200 bps.
* **Framing:** 8 data bits, no parity, 1 stop bit (8-N-1).
* **Flow Control:** None (hardware RTS/CTS lines are not wired on the standard UEXT connector).
* **eZ80 Pin Multiplexing:** `TXD1` and `RXD1` are multiplexed with Port D GPIO pins `PD4` and `PD5`. While MOS configures these at boot, custom operating system kernels or bare-metal code must ensure `PD_ALT1` and `PD_ALT2` enable the alternate function on Port D pins 4 and 5 to route signals to the UART1 hardware.
* **Power Supply & Current Transients:** The ESP8266 power amplifier consumes transient current spikes between 250 mA and 300 mA during RF packet transmission. The Agon Light 2 host power source (typically USB) must supply at least 500 mA to 1 A of clean 5V DC to prevent 3.3V rail brownouts and CPU reset events during Wi-Fi bursts.
* **Data Integrity:** Because the physical wire uses 8-N-1 without hardware parity or flow control, higher-level block storage protocols (such as virtual disk transfers) should implement protocol-level checksums (such as CRC-16) to verify data integrity against electrical noise.

### UEXT Pin Mapping

| UEXT Pin | Signal Name | ESP8266 Connection | Function / Description |
| :--- | :--- | :--- | :--- |
| **Pin 1** | `3.3V` | `VCC` | 3.3V DC power supplied by the Agon Light 2 |
| **Pin 2** | `GND` | `GND` | Common ground |
| **Pin 3** | `TXD1` | `RXD` | eZ80 UART1 Transmit (PD4) -> ESP8266 Receive (GPIO3) |
| **Pin 4** | `RXD1` | `TXD` | eZ80 UART1 Receive (PD5) <- ESP8266 Transmit (GPIO1) |
| **Pin 5** | `SCL` | *NC* | I2C clock (unused by module) |
| **Pin 6** | `SDA` | *NC* | I2C data (unused by module) |
| **Pin 7** | `MISO` | *NC* | SPI data in (unused by module) |
| **Pin 8** | `MOSI` | *NC* | SPI data out (unused by module) |
| **Pin 9** | `SCK` | *NC* | SPI clock (unused by module) |
| **Pin 10** | `CS` | *NC* | SPI chip select (unused by module) |


---

## 2. Firmware Architecture & Role

The MOD-WIFI-ESP8266 acts as an **autonomous Wi-Fi and TCP/IP network coprocessor**. 

The eZ80 CPU does not run an 802.11 MAC layer, WPA2 encryption engine, DHCP client, DNS resolver, or TCP/IP stack. All low-level network processing is offloaded to the ESP8266. The eZ80 only transmits ASCII AT commands and reads status and payload data across UART1.

### Firmware Version
* **Factory Standard:** Official **Espressif ESP-AT firmware** (v1.7.x branch, e.g., v1.7.4.0 through v1.7.6.0).
* *Note:* Standard Agon networking utilities (such as `netman`, `ping`, `ntpsync`, `telnet`, and `snail`) require Espressif's ESP-AT firmware. They are not compatible with Commodore/Hayes Zimodem firmware.

---

## 3. Operating Modes & AT Interface

The ESP-AT firmware operates in two distinct modes:

### A. Command Mode
In command mode, every transmission to the module is an ASCII command string ending in `\r\n` (`CRLF`). The module parses the command, executes the operation, and replies with ASCII response strings followed by `OK` or `ERROR`.

#### 1. Device & Wi-Fi Management
* **Ping Module:**
  ```text
  TX: AT
  RX: OK
  ```
* **Echo Control:**
  ```text
  TX: ATE1        (Enable local character echo)
  RX: OK
  TX: ATE0        (Disable local character echo)
  RX: OK
  ```
* **Set Station (Client) Mode:**
  ```text
  TX: AT+CWMODE=1       (Set Station mode, current session only)
  RX: OK
  TX: AT+CWMODE_DEF=1   (Set Station mode and commit to flash memory)
  RX: OK
  ```
* **Scan Visible Networks:**
  ```text
  TX: AT+CWLAP
  RX: +CWLAP:(3,"MyNetwork",-65,"xx:xx:xx:xx:xx:xx",1)
      OK
  ```
* **Join Wireless Access Point:**
  ```text
  TX: AT+CWJAP="MyNetwork","SecretPassword"
  RX: WIFI CONNECTED
      WIFI GOT IP
      OK
  ```
  *(If association fails, the module returns `+CWJAP:<error_code>` followed by `FAIL`, where `1` = Connection timeout, `2` = Wrong password, `3` = Target AP not found, `4` = Connection failed).*
* **Query IP Lease:**
  ```text
  TX: AT+CIPSTA?
  RX: +CIPSTA:ip:"192.168.1.50"
      +CIPSTA:gateway:"192.168.1.1"
      +CIPSTA:netmask:"255.255.255.0"
      OK
  ```
* **Query Connection Status:**
  ```text
  TX: AT+CIPSTATUS
  RX: STATUS:2
      OK
  ```
  *(Status values: `2` = Station got IP / ready, `3` = TCP/UDP transmission connected, `4` = Socket disconnected, `5` = Wi-Fi disconnected).*

#### 2. Normal Socket Mode (Framed Transfer)
* **Open Socket:**
  ```text
  TX: AT+CIPSTART="TCP","192.168.1.100",80
  RX: CONNECT
      OK
  ```
* **Send Data:**
  ```text
  TX: AT+CIPSEND=12
  RX: OK
      >
  TX: Hello World!
  RX: Recv 12 bytes
      SEND OK
  ```
* **Receive Data:**
  Incoming data from the remote host is framed with length prefixes:
  ```text
  +IPD,12:Hello World!
  ```

---

### B. Transparent Transmission (Passthrough Stream Mode)

For high-speed protocols, virtual serial bridges, block storage devices, or BBS/Telnet clients, framed transmission adds unacceptable parsing overhead. 

The module provides **UART-WiFi Passthrough Mode** (`CIPMODE=1`), which converts UART1 into a raw bidirectional TCP pipe.

#### Entering Transparent Mode:
1. Ensure single-connection mode:
   ```text
   AT+CIPMUX=0
   ```
2. Enable transparent mode:
   ```text
   AT+CIPMODE=1
   ```
3. Connect the TCP socket:
   ```text
   AT+CIPSTART="TCP","192.168.1.100",65504
   ```
4. Trigger streaming:
   ```text
   AT+CIPSEND
   ```
5. The ESP8266 responds with `OK` followed by `\r\n>`. From this moment:
   * Any byte written to UART1 is packaged directly into a TCP packet.
   * Any byte received from the TCP socket is placed directly onto UART1 without `+IPD` wrappers.
   * AT commands are ignored.
   * **Packetization Latency:** The ESP8266 automatically flushes buffered serial data into a TCP packet when either 2,048 bytes accumulate or a **20 ms silence interval** occurs on UART1. For small request/response transactions, this 20 ms idle threshold introduces a fixed round-trip latency floor.

#### Exiting Transparent Mode:
To break out of transparent stream mode back to AT command mode, the host must send the standard Hayes escape sequence with strict guard timing:

1. **Pre-guard delay:** Maintain at least 1.0 second of total silence (no bytes sent over UART1).
2. **Escape sequence:** Send exactly three plus characters: `+++` (do not append `\r` or `\n`).
3. **Post-guard delay:** Wait at least 1.0 second of total silence.
4. **No Response Warning:** The ESP8266 emits **no response token (such as `OK`)** upon escaping via `+++`. Software must not block waiting for an acknowledgment; after the 1.0-second post-guard silence, the module is ready to accept regular AT commands.
5. **Close socket:** Send `AT+CIPCLOSE\r\n`.

---

## 4. ESP-AT Command Reference & Architecture for Streaming

The MOD-WIFI-ESP8266's ESP-AT firmware provides the complete command set necessary to manage wireless connectivity, configure network persistence, and maintain high-speed TCP streaming sessions.

### Command Reference Table

| AT Command | Syntax / Example | Scope & Persistence | Purpose & Functional Behavior |
| :--- | :--- | :--- | :--- |
| `ATE` | `ATE1` / `ATE0` | RAM (Current Session) | Enables or disables command character echo on UART1. |
| `AT+CWMODE_DEF` | `AT+CWMODE_DEF=1` | Flash (Persistent) | Sets Station mode, disabling default SoftAP broadcast and saving to flash. |
| `AT+CWDHCP_DEF` | `AT+CWDHCP_DEF=1,1` | Flash (Persistent) | Enables automatic DHCP IP assignment for Station mode and saves to flash. |
| `AT+CWJAP_DEF` | `AT+CWJAP_DEF="SSID","PASS"` | Flash (Persistent) | Associates with the designated AP and commits credentials to flash for automatic reconnection. |
| `AT+CIPSTA_CUR?` | `AT+CIPSTA_CUR?` | RAM (Query) | Queries the currently assigned IP address, gateway, and subnet mask from active memory. |
| `AT+CIPSTATUS` | `AT+CIPSTATUS` | RAM (Query) | Queries connection status (`2` = Got IP, `3` = Connected, `4` = Disconnected, `5` = Wi-Fi lost). |
| `AT+CIPMUX` | `AT+CIPMUX=0` | RAM (Current Session) | Enforces single-connection mode (mandatory prerequisite for transparent streaming). |
| `AT+CIPMODE` | `AT+CIPMODE=1` | RAM (Current Session) | Activates transparent UART-to-WiFi passthrough transmission mode. |
| `AT+CIPSTART` | `AT+CIPSTART="TCP","host",port` | RAM (Current Session) | Establishes the outbound TCP socket connection to the remote server. |
| `AT+CIPSEND` | `AT+CIPSEND` | RAM (Current Session) | In `CIPMODE=1`, triggers unvarnished streaming mode and returns the `>` prompt. |
| `+++` | `+++` (1s guard times) | Immediate | Standard Hayes escape sequence to exit streaming mode (silently returns to AT mode, no `OK`). |
| `AT+CIPCLOSE` | `AT+CIPCLOSE` | Immediate | Cleanly terminates the active TCP socket connection. |


### Architectural Features of the MOD-WIFI-ESP8266

1. **Flash Parameter Persistence (`_DEF` vs `_CUR`):**
   * The ESP-AT firmware differentiates between transient and persistent configurations using `_CUR` (current RAM state) and `_DEF` (default flash memory).
   * Storing Wi-Fi configuration with `_DEF` commands (`CWMODE_DEF`, `CWDHCP_DEF`, `CWJAP_DEF`) means the MOD-WIFI-ESP8266 automatically re-associates with your wireless router and renews its DHCP lease upon every power-up without requiring any configuration code to run on the eZ80.

2. **Asynchronous Status Notification:**
   * The ESP8266 emits asynchronous status strings during connection lifecycle events:
     * `WIFI CONNECTED`: Association with the 802.11 AP succeeded.
     * `WIFI GOT IP`: DHCP lease acquired from the local network router.
     * `CONNECT`: Outbound TCP three-way handshake completed.
     * `CLOSED`: Remote server or local module terminated the TCP connection.
     * `OK` / `ERROR`: Standard AT command completion status.

3. **Strict Hayes Escape Guard Timing:**
   * When escaping from transparent passthrough mode, the module requires at least 1.0 second of silence before the `+++` string, and at least 1.0 second of silence after. Sending characters immediately before or appending `\r\n` to `+++` will cause the ESP8266 to treat the plus characters as raw socket payload data rather than a mode escape trigger.

---

## 5. Software Access, Buffering & Flow Control Architecture

On the Agon Light 2, the eZ80 communicates with the MOD-WIFI-ESP8266 across the dedicated serial interface on UART1. Because the standard UEXT connector routes only TXD1 and RXD1 (3.3V TTL) without hardware flow control lines (RTS/CTS), serial communication relies entirely on hardware FIFOs, interrupt service routines, and multi-tier software buffers on both the host and the coprocessor.

### A. Software Access Interfaces
Software running on the eZ80 can interface with UART1 at two levels:
* **High-Level MOS APIs:** Standard MOS system calls (`mos_uopen`, `mos_uclose`, `mos_ugetc`, `mos_uputc`) that manage serial framing and operate against an interrupt-driven software circular buffer in eZ80 RAM.
* **Direct Hardware Register Access:** Direct I/O access to the eZ80 UART1 registers to maximize throughput and eliminate operating system overhead during high-speed streaming:
  * `UART1_RBR` (I/O `$D0`, DLAB=0, Read): Receiver Buffer Register (reads top of 16-byte RX FIFO).
  * `UART1_THR` (I/O `$D0`, DLAB=0, Write): Transmitter Holding Register (writes to TX shift register/FIFO).
  * `UART1_IER` (I/O `$D1`, DLAB=0): Interrupt Enable Register (Bit 0 = `RIE` receiver interrupt, Bit 1 = `TIE` transmit empty interrupt, Bit 3 = `MSIE` modem status interrupt).
  * `UART1_IIR` / `UART1_FCR` (I/O `$D2`): Shared address. Reading returns the Interrupt Identification Register (`IIR`). Writing configures the FIFO Control Register (`FCR`): Bit 0 (`FIFOEN`) enables the 16-byte hardware FIFOs, Bits 1–2 clear FIFOs, and Bits 6–7 select the RX FIFO trigger threshold (00 = 1 byte, 01 = 4 bytes, 10 = 8 bytes, 11 = 14 bytes).
  * `UART1_LCR` (I/O `$D3`): Line Control Register. Bits 0–1 set character length (11 = 8 bits). Bit 7 is `DLAB` (Divisor Latch Access Bit), which must be set to 1 to write baud divisor registers and cleared to 0 for normal data I/O.
  * `UART1_LSR` (I/O `$D5`): Line Status Register. Bit 0 = `DR` (Data Ready), Bit 1 = `OE` (Overrun Error), Bit 5 = `THRE` (Transmitter Holding Register Empty), Bit 6 = `TEMT` (Transmitter Empty).
  * `UART1_BRG_L` / `UART1_BRG_H` (I/O `$D0`/`$D1`, DLAB=1): Baud Rate Generator divisor registers. For a system clock of 18.432 MHz and target baud rate of 115,200 bps:
    $$\text{Divisor} = \frac{18,432,000}{16 \times 115,200} = 10 \quad (\text{0x000A})$$
    Setting `BRG_L = 10` and `BRG_H = 0` produces exact 115,200 baud with 0.00% clock timing error.


### B. Incoming Character Detection & Alerting Architecture
While modem status lines (like CTS, DSR, DCD, and RI) historically triggered UART Modem Status Interrupts (`MSIE`) to signal carrier and line state changes, they do not pulse on individual character arrivals:
* **Asynchronous Start-Bit Detection:** Incoming characters are detected directly on the `RXD1` pin via start-bit falling-edge detection, shifting serial data into the 16-byte hardware receiver FIFO.
* **Interrupt-Driven Alerting:** Setting the Receiver Interrupt Enable (`RIE`) bit in `UART1_IER` raises the `UART1_IVECT` interrupt when the FIFO reaches its configured threshold (1, 4, 8, or 14 bytes) or upon a character timeout.
* **Polled Alerting:** Dedicated drivers running with interrupts disabled poll the Data Ready (`DR`) status flag in `UART1_LSR` to immediately extract characters as they land in `UART1_RBR`.

### C. Multi-Tier Coprocessor Buffering
The MOD-WIFI-ESP8266 is an autonomous, deeply buffered network coprocessor rather than an unbuffered serial device. Characters transmitted by the eZ80 are staged through three distinct layers:
1. **Hardware UART RX FIFO (128 bytes):** Captures incoming wire bursts directly at 115,200 baud.
2. **ESP-AT Driver Ring Buffer (512–2048 bytes):** A high-priority firmware ISR continuously offloads the hardware FIFO into an internal RAM buffer.
3. **LwIP TCP Socket Buffers (Up to 2048 bytes per segment):** In transparent streaming mode (`CIPMODE=1`), the coprocessor aggregates stream data into TCP segments, transmitting them over Wi-Fi when the buffer reaches 2,048 bytes or upon a 20 ms UART idle timeout.

### D. Timing Margins & Flow Control Semantics
* **Host Receiver Headroom:** Although an empty 16-byte FIFO takes approximately 1.38 ms to fill at 115,200 baud (86.8 µs per character), interrupt-driven systems fire at intermediate thresholds. When configured with a 14-byte trigger level, the CPU has a strict 2-character margin (approximately 174 µs) to enter the ISR and service the FIFO before an overrun error (`OE`) occurs.
* **Layer 4 Flow Control vs. Wire Throttling:** Physical RTS/CTS originated in telecommunications for half-duplex carrier turnaround and was only later co-opted for buffer pacing. In this architecture, wire-level throttling is unnecessary because end-to-end backpressure is handled at Layer 4 by TCP sliding windows between the ESP8266 and the remote server.
* **Bandwidth & Latency Asymmetry:** Normal Wi-Fi throughput vastly exceeds the 11.5 KB/s serial rate, allowing the coprocessor to drain its buffers near-instantaneously. However, firmware latency spikes on the ESP8266 (such as RF calibration or beacon resynchronization lasting 5–15 ms) can occasionally threaten its 128-byte hardware FIFO (which fills in 11.1 ms).

### E. Driver Modernization: Adapting Legacy Serial Drivers for Streaming
Legacy operating system drivers (such as the TRS-OS network client) were architected around unbuffered null-modem serial cables, employing per-character RTS/CTS stop-and-wait handshaking (asserting RTS, polling CTS, and waiting on every single byte). When interfacing with the MOD-WIFI-ESP8266 on UEXT, drivers should be restructured conceptually:

* **Eliminate Hardware CTS Polling:** Remove routines that poll CTS in the Modem Status Register (`UART1_MSR`). On UEXT, the CTS pin is floating or unrouted; polling it results in permanent driver deadlocks or timeouts. Outbound readiness should be determined solely by checking the Transmitter Holding Register Empty (`THRE`) flag in `UART1_LSR`.
* **Eliminate Per-Byte RTS Toggling:** Strip out the port writes that toggle RTS in the Modem Control Register (`UART1_MCTL`) before and after each character read. The ESP8266 has no RTS connection and cannot see this signal; removing these cycles reclaims substantial CPU time.
* **Transition from Byte-by-Byte to Block-Level Transfers:** For block devices (such as virtual disk sector transfers of 256 bytes), replace repetitive single-byte driver dispatch calls with tightly coupled, inline burst loops. Because an 18.432 MHz eZ80 polling loop consumes less than 1 µs per iteration compared to the 86.8 µs character arrival time, the host easily outpaces the incoming serial stream without requiring wire-level flow control.
* **Rely on Protocol-Level Request-Response Framing:** Instead of pacing each byte over the physical wire, rely on the inherently half-duplex nature of disk request/response transactions and TCP sliding windows to prevent buffer starvation or overflows.

---

## 6. End-to-End Operational Roadmap (UART1 TCP/IP Streaming)

This roadmap outlines the complete lifecycle for establishing and managing a transparent TCP/IP communication stream between the Agon Light 2 and a remote server (e.g., FujiNet, DriveWire server, BBS, or custom file server) using UART1.

### Operational Lifecycle Overview

```
+-------------------------------------------------------------------------------+
| PHASE 1: One-Time Wi-Fi Provisioning (Run once; persisted to flash)           |
|   Open UART1 (115200 8N1) -> AT+CWMODE_DEF=1 -> AT+CWDHCP_DEF=1,1            |
|   -> AT+CWJAP_DEF="SSID","PASS" -> Wait for "WIFI GOT IP" -> AT+CIPSTA_CUR?   |
+---------------------------------------+---------------------------------------+
                                        |
  (Subsequent reboots: Wi-Fi auto-connects to AP from Flash without Phase 1)
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 2: Connection Establishment & Passthrough Activation (Run per session)  |
|   Verify Wi-Fi link (AT+CIPSTA?)                                              |
|   -> Set single connection: AT+CIPMUX=0                                       |
|   -> Enable transparent mode: AT+CIPMODE=1                                    |
|   -> Connect TCP socket: AT+CIPSTART="TCP","host",port -> Wait for "CONNECT"   |
|   -> Enter stream mode: AT+CIPSEND -> Wait for ">" prompt                     |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 3: Active Bidirectional Streaming                                       |
|   Direct UART1 byte transfers <========================> Raw TCP payload data |
|   (Zero packet framing overhead / full 115,200 baud continuous stream)        |
+---------------------------------------+---------------------------------------+
                                        |
                                        v
+-------------------------------------------------------------------------------+
| PHASE 4: Clean Teardown & Disconnection                                       |
|   1.0s Pre-Guard silence window                                               |
|   -> Send escape string: "+++" (No CR or LF)                                  |
|   -> 1.0s Post-Guard silence window                                           |
|   -> Issue socket close: AT+CIPCLOSE -> Wait for "CLOSED OK"                  |
|   -> Restore normal mode: AT+CIPMODE=0                                        |
|   -> Drain UART1 RX FIFO & close UART1 or return to MOS                       |
+-------------------------------------------------------------------------------+
```

### Phase 1: One-Time Wi-Fi Provisioning (Flash Persistence)

This sequence is executed **only once** to pair the MOD-WIFI-ESP8266 with your local Wi-Fi router. Because the `_DEF` commands write configuration directly to the ESP8266's internal flash memory, the module automatically reconnects to this access point and acquires an IP address via DHCP upon every subsequent power-up.

1. **Initialize UART1:**
   Open UART1 at 115,200 baud, 8-N-1. Read and discard any residual characters currently residing in the receive FIFO.

2. **Verify Module Presence:**
   ```text
   TX: AT\r\n
   RX: OK\r\n
   ```

3. **Set Station Mode (Persist to Flash):**
   ```text
   TX: AT+CWMODE_DEF=1\r\n
   RX: OK\r\n
   ```

4. **Enable DHCP Client (Persist to Flash):**
   ```text
   TX: AT+CWDHCP_DEF=1,1\r\n
   RX: OK\r\n
   ```

5. **Associate with Access Point (Persist to Flash):**
   ```text
   TX: AT+CWJAP_DEF="MyWiFiSSID","MyWiFiPassword"\r\n
   ```
   Wait for the asynchronous association and DHCP handshake messages (may take up to 5-10 seconds):
   ```text
   RX: WIFI CONNECTED\r\n
       WIFI GOT IP\r\n
       \r\n
       OK\r\n
   ```

6. **Verify Network Parameters:**
   ```text
   TX: AT+CIPSTA_CUR?\r\n
   RX: +CIPSTA_CUR:ip:"192.168.1.50"\r\n
       +CIPSTA_CUR:gateway:"192.168.1.1"\r\n
       +CIPSTA_CUR:netmask:"255.255.255.0"\r\n
       \r\n
       OK\r\n
   ```

*From this point forward, Phase 1 is complete and never needs to be re-run unless the Wi-Fi credentials change.*

---

### Phase 2: Connection Establishment & Passthrough Activation

This sequence is executed by software whenever it needs to initiate a network session with a remote server.

1. **Verify Wi-Fi Link Readiness:**
   Since the ESP8266 auto-associates at boot from flash parameters, query its connection state:
   ```text
   TX: AT+CIPSTATUS\r\n
   RX: STATUS:2
       OK\r\n
   ```
   *Note: `STATUS:2` confirms the station has successfully acquired a DHCP IP address and is ready for socket connections. If `STATUS:5`, the module is still associating.*

2. **Enforce Single-Connection Mode:**
   Transparent streaming strictly requires single-connection mode (`CIPMUX=0`).
   ```text
   TX: AT+CIPMUX=0\r\n
   RX: OK\r\n
   ```

3. **Enable Transparent Passthrough Mode:**
   Configure the serial engine for UART-to-WiFi passthrough:
   ```text
   TX: AT+CIPMODE=1\r\n
   RX: OK\r\n
   ```

4. **Connect TCP Socket to Remote Server:**
   Initiate the outbound connection (specify target host and port):
   ```text
   TX: AT+CIPSTART="TCP","192.168.1.100",65504\r\n
   ```
   Allow up to 3 seconds for the TCP three-way handshake (`SYN`, `SYN-ACK`, `ACK`). The module responds with:
   ```text
   RX: CONNECT\r\n
       \r\n
       OK\r\n
   ```

5. **Activate Continuous Streaming Mode:**
   Send `AT+CIPSEND` without length arguments:
   ```text
   TX: AT+CIPSEND\r\n
   ```
   The module returns confirmation followed by the prompt token:
   ```text
   RX: \r\nOK\r\n
       \r\n>
   ```
   Wait until the `>` character is received across UART1. The stream is now open.

---

### Phase 3: Active Bidirectional Streaming

Once the `>` prompt is received, the module enters unvarnished transparent streaming mode:

* **Outbound Traffic:** Every byte transmitted by the eZ80 to UART1 (`UART1_THR` or `mos_uputc`) is encapsulated directly into outbound TCP packets by the ESP8266.
* **Inbound Traffic:** Inbound TCP data received from the remote server is unbundled by the ESP8266 and placed directly into the UART1 receive register (`UART1_RBR` or `mos_ugetc`) with no protocol headers, checksum wrappers, or `+IPD` frames.
* **Flow Control / Throughput:** The link operates at the full 115,200 baud rate (~11.5 KB/sec raw throughput). Because hardware flow control (RTS/CTS) is not wired on UEXT, the receiving software should read UART1 promptly or use interrupt-driven ring buffers to avoid RX FIFO overruns.

---

### Phase 4: Clean Teardown & Full Disconnection

When the application finishes or needs to close the remote session, it must break out of streaming mode, terminate the TCP socket, and flush the serial interface to prevent stale data from corrupting future operations.

1. **Step 1: Enforce Pre-Guard Silence:**
   Stop all data transmission across UART1. Maintain complete silence (no bytes sent) for a minimum of **1.0 second (1,000 ms)**.
   *Note: If any characters are transmitted during this window, the ESP8266 will not recognize the subsequent escape sequence.*

2. **Step 2: Transmit Hayes Escape Sequence:**
   Send exactly three ASCII plus characters with no line terminators:
   ```text
   TX: +++
   ```
   *Note: Do NOT send `\r` (`0x0D`) or `\n` (`0x0A`). Sending `+++\r\n` will cause the module to treat the plus signs as regular socket payload data.*

3. **Step 3: Enforce Post-Guard Silence:**
   Maintain complete silence for another minimum of **1.0 second (1,000 ms)**.
   During this pause, the ESP8266 detects the guard boundary, suspends transparent streaming, and switches back to AT command mode.
   *Important: The ESP8266 emits NO response string (such as `OK`) upon escaping via `+++`. Software must not wait for an acknowledgment; after the 1.0-second delay, the module is ready to accept commands.*

4. **Step 4: Close the TCP Socket:**
   Send the close command:
   ```text
   TX: AT+CIPCLOSE\r\n
   ```
   Wait approximately 500 ms to 1.0 second for the remote host and ESP8266 to exchange TCP `FIN` / `ACK` packets.
   The ESP8266 emits:
   ```text
   RX: CLOSED\r\n
       \r\n
       OK\r\n
   ```

5. **Step 5: Flush Receive Buffers:**
   Read and discard all incoming bytes from UART1 until the receive buffer is completely empty. This ensures leftover strings (`CLOSED`, `OK`) are not mistakenly read as data by subsequent routines.

6. **Step 6: Reset Mode to Standard (Defensive Teardown):**
   Disable transparent transmission mode so the module returns to standard command processing:
   ```text
   TX: AT+CIPMODE=0\r\n
   RX: OK\r\n
   ```

7. **Step 7: Release UART1:**
   Close the UART1 channel via `mos_uclose` or reconfigure it as required by your application.

