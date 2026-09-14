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

### UEXT Pin Mapping

| UEXT Pin | Signal Name | ESP8266 Connection | Function / Description |
| :--- | :--- | :--- | :--- |
| **Pin 1** | `3.3V` | `VCC` | 3.3V DC power supplied by the Agon Light 2 |
| **Pin 2** | `GND` | `GND` | Common ground |
| **Pin 3** | `TXD1` | `RXD` | eZ80 UART1 Transmit -> ESP8266 Receive |
| **Pin 4** | `RXD1` | `TXD` | eZ80 UART1 Receive <- ESP8266 Transmit |
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
* **Query IP Lease:**
  ```text
  TX: AT+CIPSTA?
  RX: +CIPSTA:ip:"192.168.1.50"
      +CIPSTA:gateway:"192.168.1.1"
      +CIPSTA:netmask:"255.255.255.0"
      OK
  ```

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
  RX: SEND OK
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

#### Exiting Transparent Mode:
To break out of transparent stream mode back to AT command mode, the host must send the standard Hayes escape sequence with strict guard timing:

1. **Pre-guard delay:** Maintain at least 1.0 second of total silence (no bytes sent over UART1).
2. **Escape sequence:** Send exactly three plus characters: `+++` (do not append `\r` or `\n`).
3. **Post-guard delay:** Wait at least 1.0 second of total silence.
4. **Close socket:** Send `AT+CIPCLOSE\r\n`.

---

## 4. ESP-AT Command Reference & Architecture for Streaming

The MOD-WIFI-ESP8266's ESP-AT firmware provides the complete command set necessary to manage wireless connectivity, configure network persistence, and maintain high-speed TCP streaming sessions.

### Command Reference Table

| AT Command | Syntax / Example | Scope & Persistence | Purpose & Functional Behavior |
| :--- | :--- | :--- | :--- |
| `ATE` | `ATE1` / `ATE0` | RAM (Current Session) | Enables or disables command character echo on UART1. |
| `AT+CWMODE_DEF` | `AT+CWMODE_DEF=1` | Flash (Persistent) | Sets Station (Wi-Fi client) mode and stores it in flash memory across reboots. |
| `AT+CWDHCP_DEF` | `AT+CWDHCP_DEF=1,1` | Flash (Persistent) | Enables automatic DHCP IP assignment for Station mode and saves to flash. |
| `AT+CWJAP_DEF` | `AT+CWJAP_DEF="SSID","PASS"` | Flash (Persistent) | Associates with the designated AP and commits credentials to flash for automatic reconnection. |
| `AT+CIPSTA_CUR?` | `AT+CIPSTA_CUR?` | RAM (Query) | Queries the currently assigned IP address, gateway, and subnet mask from active memory. |
| `AT+CIPMUX` | `AT+CIPMUX=0` | RAM (Current Session) | Enforces single-connection mode (mandatory prerequisite for transparent streaming). |
| `AT+CIPMODE` | `AT+CIPMODE=1` | RAM (Current Session) | Activates transparent UART-to-WiFi passthrough transmission mode. |
| `AT+CIPSTART` | `AT+CIPSTART="TCP","host",port` | RAM (Current Session) | Establishes the outbound TCP socket connection to the remote server. |
| `AT+CIPSEND` | `AT+CIPSEND` | RAM (Current Session) | In `CIPMODE=1`, triggers unvarnished streaming mode and returns the `>` prompt. |
| `+++` | `+++` (1s guard times) | Immediate | Standard Hayes escape sequence to exit streaming mode and return to AT command mode. |
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

On the Agon Light 2, the eZ80 communicates with the MOD-WIFI-ESP8266 across the dedicated serial interface on UART1. Because the standard UEXT connector does not route hardware flow control lines (RTS/CTS), serial communication relies on hardware FIFOs, interrupt service routines, and multi-tier software buffers on both the eZ80 host and the ESP8266 coprocessor.

### A. MOS API Calls
Under MOS, programs can interact with UART1 via system calls:

* **`mos_uopen`:** Initializes and configures UART1 baud rate, data bits, stop bits, and parity.
* **`mos_uclose`:** Closes the UART1 interface and releases buffers.
* **`mos_ugetc`:** Reads an incoming character from the UART1 receive buffer.
* **`mos_uputc`:** Transmits an outgoing character across UART1.

### B. Direct eZ80 Hardware Register Access
For maximum throughput during transparent mode (such as block storage or raw streaming), software can bypass MOS and access the eZ80 UART1 hardware registers directly:

* `UART1_RBR` / `UART1_THR`: Receive Buffer Register / Transmitter Holding Register.
* `UART1_LSR`: Line Status Register (checks transmitter empty and receiver data ready bits).
* `UART1_IER`: Interrupt Enable Register.
* `UART1_BRG_L` / `UART1_BRG_H`: Baud Rate Generator registers for setting 115,200 baud.

### C. Incoming Character Detection on the eZ80 (RX Architecture)
RTS/CTS lines perform transmission throttling rather than character notification. On the Agon Light 2, the eZ80 detects incoming characters from the ESP8266 using either hardware interrupts or register polling:

1. **Hardware Interrupt-Driven RX (Standard MOS Architecture):**
   * The eZ80 features a 16550-compatible UART with an internal **16-byte hardware RX FIFO**.
   * Setting bit 0 (`RIE` — Receiver Interrupt Enable) in `UART1_IER` causes the UART to assert the `UART1_IVECT` vectored interrupt under two conditions:
     * **FIFO Trigger Threshold:** The number of received bytes in the FIFO reaches a preconfigured level (1, 4, 8, or 14 bytes).
     * **Character Timeout:** Unread characters remain in the FIFO for approximately 4 character durations without new bytes arriving.
   * The MOS UART1 Interrupt Service Routine (ISR) intercepts this vector, unloads bytes from `UART1_RBR`, and inserts them into an in-memory **circular ring buffer** in eZ80 RAM. Applications retrieve characters asynchronously by calling `mos_ugetc()`.

2. **Direct Register Polling (Polled Driver Loops):**
   * In tight, dedicated driver loops where interrupts are disabled, software continuously checks bit 0 (`DR` — Data Ready) of the Line Status Register (`UART1_LSR`).
   * When `DR` is `1`, at least one unread character is available in `UART1_RBR`. Reading `UART1_RBR` clears the `DR` bit until the next byte arrives:
     ```assembly
     poll_rx:   in0   a, (UART1_LSR)
                bit   0, a              ; Check DR (Data Ready) bit
                jr    z, poll_rx        ; Loop until a character arrives
                in0   a, (UART1_RBR)    ; Read byte from receiver register
     ```

### D. Outgoing Buffering & Packetization on the ESP8266 (TX Architecture)
Characters transmitted by the eZ80 across UART1 are captured and buffered across three distinct layers inside the MOD-WIFI-ESP8266:

1. **ESP8266 Hardware RX FIFO (128 bytes):**
   The ESP8266 UART input is backed by a physical 128-byte hardware FIFO that receives incoming serial bytes directly from the wire.
2. **ESP-AT Firmware Ring Buffer (512 to 2048 bytes):**
   A dedicated high-priority interrupt handler in the ESP-AT firmware continuously drains the 128-byte hardware FIFO into an allocated circular ring buffer in ESP8266 RAM.
3. **LwIP TCP Socket Buffers (Up to 2048 bytes per packet):**
   In transparent streaming mode (`CIPMODE=1`), the ESP8266 batches buffered UART data into TCP segments. A TCP packet is transmitted over Wi-Fi when either:
   * A total of **2,048 bytes** accumulate in the buffer, or
   * A **20 ms silence interval** (no new serial characters) occurs on UART1.

### E. Flow Control & Timing Constraints Without RTS/CTS

1. **Absence of Host Throttling:**
   Because no physical RTS line connects from the eZ80 to the ESP8266, the eZ80 cannot signal the ESP8266 to pause transmission. If the eZ80 disables interrupts or fails to service `UART1_RBR` while data is arriving, the 16-byte hardware FIFO will overflow, setting the Overrun Error bit (`OE`, bit 1 in `UART1_LSR`) and discarding subsequent bytes.
   * At **115,200 baud**, one byte arrives every **86.8 microseconds**.
   * At **18.432 MHz**, the eZ80 executes approximately **1,600 clock cycles per incoming byte**.
   * The 16-byte hardware FIFO affords a maximum grace period of **1.38 milliseconds** before an overrun occurs.

2. **Bandwidth Asymmetry:**
   Under normal conditions, buffer overruns do not occur on the ESP8266 during host-to-module transmission:
   * **UART1 Transmit Bandwidth:** 115,200 baud yields approximately **11.5 KB/s**.
   * **Wi-Fi Transmit Bandwidth:** 802.11n Wi-Fi operates at **hundreds of kilobytes to megabytes per second**.
   Because the Wi-Fi transmission pipe is orders of magnitude faster than the serial input, the ESP8266 empties its buffers nearly instantaneously.

3. **Network Stalls & Backpressure:**
   If the remote TCP host stops acknowledging packets (TCP window exhaustion) or the Wi-Fi connection drops, the ESP8266's internal TCP and UART buffers will eventually fill completely. Without a CTS line to throttle the eZ80, continued serial transmission during an unacknowledged network stall will cause the ESP8266's internal buffers to overflow, resulting in lost transmit bytes.

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
   Since the ESP8266 auto-associates at boot, query its current IP address to confirm connectivity:
   ```text
   TX: AT+CIPSTA?\r\n
   RX: +CIPSTA:ip:"192.168.1.50"
       +CIPSTA:gateway:"192.168.1.1"
       +CIPSTA:netmask:"255.255.255.0"
       OK\r\n
   ```
   If the IP address is `0.0.0.0`, wait 1-2 seconds and retry.

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

