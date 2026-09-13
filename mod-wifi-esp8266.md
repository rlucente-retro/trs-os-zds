# Olimex MOD-WIFI-ESP8266 on Olimex Agon Light 2

This document describes how the **Olimex MOD-WIFI-ESP8266** module interfaces with the **Olimex Agon Light 2** retrocomputer, details its AT modem command interface, and analyzes its compatibility with the WIZnet WizFi360 AT sequence used in NitrOS-9 (`establish_wizfi.md` and `terminate_wizfi.md`).

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

## 4. Comparison with WIZnet WizFi360 (NitrOS-9 Wildbits)

The WIZnet WizFi360 module used on the Wildbits hardware platform running NitrOS-9 Level 2 (`establish_wizfi.md` and `terminate_wizfi.md`) was deliberately engineered as an AT-compatible and pin-compatible alternative to the Espressif ESP8266.

Consequently, **the MOD-WIFI-ESP8266 accepts the exact same AT command sequence.**

### Command Compatibility Matrix

| NitrOS-9 WizFi360 Command | ESP8266 ESP-AT Equivalent | Compatibility & Notes |
| :--- | :--- | :--- |
| `ATE1` | `ATE1` | **Identical.** Enables local command echo. |
| `AT+CWMODE_DEF=1` | `AT+CWMODE_DEF=1` | **Identical.** Station mode committed to flash. |
| `AT+CWDHCP_DEF=1,1` | `AT+CWDHCP_DEF=1,1` | **Identical.** Enables DHCP client on Station mode and saves to flash. |
| `AT+CWJAP_DEF="ssid","pass"` | `AT+CWJAP_DEF="ssid","pass"` | **Identical.** Stores SSID/password in flash and auto-connects on boot. |
| `AT+CIPSTA_CUR?` | `AT+CIPSTA_CUR?` | **Identical.** Queries current IP lease details from RAM. |
| `AT+CIPMUX=0` | `AT+CIPMUX=0` | **Identical.** Enforces single-connection mode (prerequisite for `CIPMODE=1`). |
| `AT+CIPMODE=1` | `AT+CIPMODE=1` | **Identical.** Enables transparent UART-WiFi passthrough. |
| `AT+CIPSTART="TCP",...` | `AT+CIPSTART="TCP",...` | **Identical.** Establishes outbound TCP socket connection. |
| `AT+CIPSEND` | `AT+CIPSEND` | **Identical.** Enters raw streaming mode; emits `OK` then `>`. |
| `+++` (with 1s guard times) | `+++` (with 1s guard times) | **Identical.** Hayes escape sequence to exit streaming mode. |
| `AT+CIPCLOSE` | `AT+CIPCLOSE` | **Identical.** Closes the open socket. |

### Technical Details Shared by Both Modules

1. **`_DEF` vs `_CUR` Persistence Suffixes:**
   * Espressif introduced the `_DEF` (default / flash-persisted) and `_CUR` (current / RAM-only) suffixes in ESP-AT v1.0. WIZnet replicated this design.
   * Storing parameters with `_DEF` means that on any subsequent reboot or power-on, the ESP8266 automatically associates with the network and acquires an IP address without host intervention.

2. **Asynchronous Status Responses:**
   * Status strings emitted by the ESP8266 during connection lifecycle match the WizFi360:
     * `WIFI CONNECTED`
     * `WIFI GOT IP`
     * `CONNECT`
     * `CLOSED`
     * `OK` / `ERROR`

3. **Guard Delay Rules:**
   * Both modules require 1.0 second of silence before and after `+++`. Sending characters immediately before or appending `\r\n` to `+++` will cause the module to treat the plus signs as raw socket payload data rather than an escape command.

---

## 5. Software Access on the Agon Light 2

Unlike the Wildbits platform (which interfaces to the WizFi360 through memory-mapped FPGA FIFO registers at `$FF20`–`$FF2F`), the Agon Light 2 accesses the MOD-WIFI-ESP8266 through standard UART serial I/O.

### MOS API Calls
Under MOS, programs can interact with UART1 via system calls:

* **`mos_uopen`:** Initializes and configures UART1 baud rate, data bits, stop bits, and parity.
* **`mos_uclose`:** Closes the UART1 interface and releases buffers.
* **`mos_ugetc`:** Reads an incoming character from the UART1 receive buffer.
* **`mos_uputc`:** Transmits an outgoing character across UART1.

### Direct eZ80 Hardware Register Access
For maximum throughput during transparent mode (such as block storage or raw streaming), software can bypass MOS and access the eZ80 UART1 hardware registers directly:

* `UART1_RBR` / `UART1_THR`: Receive Buffer Register / Transmitter Holding Register.
* `UART1_LSR`: Line Status Register (checks transmitter empty and receiver data ready bits).
* `UART1_IER`: Interrupt Enable Register.
* `UART1_BRG_L` / `UART1_BRG_H`: Baud Rate Generator registers for setting 115,200 baud.
