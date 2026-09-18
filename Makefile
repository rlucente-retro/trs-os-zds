# ==============================================================================
# Makefile - TRS-OS (TRSDOS 7) Build Automation for macOS
# Target Platform: Olimex Agon Light 2 (Zilog eZ80F92 @ 18.432 MHz)
# Peripheral     : Olimex MOD-WIFI-ESP8266 on 10-pin UEXT connector (UART1)
# ==============================================================================

SHELL        := /bin/bash

# URLs
TRSDOS_URL   := https://www.danielpaulmartin.com/sitepad-data/uploads/TRSDOS_7.zip
ZILOG_URL    := https://www.zilog.com/index.php?option=com_zcm&task=view&soft_id=54&Itemid=74

# Tools & Wine paths
WINE         ?= wine64
ZDS_DIR      ?= $(HOME)/.wine/drive_c/Zilog/ZDSII_eZ80Acclaim!_5.3.5
AS           := $(WINE) "$(ZDS_DIR)/bin/ez80asm.exe"
LD           := $(WINE) "$(ZDS_DIR)/bin/eZ80link.exe"
HEX2BIN      ?= hex2bin

CPU          ?= eZ80F91
SRC_DIR      := TRSDOS_7
GLOBAL_DIR   := TRSDOS_GLOBAL
PATCH_DIR    := patches
PATCHES      := $(sort $(wildcard $(PATCH_DIR)/*.patch))
PATCH_STAMP  := $(SRC_DIR)/.patched
TARGET_HEX   := $(SRC_DIR)/TRSDOS.hex
TARGET_LOD   := $(SRC_DIR)/TRSDOS.lod
TARGET_OBJ   := $(SRC_DIR)/TRSDOS.obj
TARGET_BIN   := $(SRC_DIR)/TRSDOS.bin
LINKCMD      := $(SRC_DIR)/TRSDOS_macos.linkcmd
UPSTREAM_HEX := $(SRC_DIR)/debug/TRSDOS.hex

# Include search paths for ZDS II ez80asm.exe
INCLUDES     := SYSRES;\
SYSRES\\drivers;\
SYSRES\\interrupts;\
SYSRES\\lowcore;\
SYSRES\\memory;\
SYSRES\\restarts;\
SYSRES\\SVC;\
..\\TRSDOS_GLOBAL;\
..\\TRSDOS_GLOBAL\\equates;\
..\\TRSDOS_GLOBAL\\macros;\
..\\TRSDOS_GLOBAL\\macros\\D_language_macros;\
..\\TRSDOS_GLOBAL\\macros\\DD_language_macros;\
..\\TRSDOS_GLOBAL\\macros\\network_macros;\
SYS0_IPL;\
SYS0_IPL\\screens;\
C:\\Zilog\\ZDSII_eZ80Acclaim!_5.3.5\\include\\std;\
C:\\Zilog\\ZDSII_eZ80Acclaim!_5.3.5\\include\\zilog

ASFLAGS      := -define:_EZ80ACCLAIM!=1 \
                -include:"$(INCLUDES)" \
                -list -listmac -name -pagelen:66 -pagewidth:132 \
                -quiet -NOsdiopt -warn -debug -NOigcase -cpu:$(CPU)

.PHONY: all fetch fetch-zds install-zds patch verify clean distclean check-env

all: check-env $(SRC_DIR)/TRSDOS.s $(PATCH_STAMP) $(LINKCMD) $(TARGET_HEX) $(TARGET_BIN)

# Verify environment prerequisites
check-env:
	@command -v $(WINE) > /dev/null 2>&1 || { \
		echo "Error: '$(WINE)' not found."; \
		echo "Please install Apple's Game Porting Toolkit wine64:"; \
		echo "  brew tap gcenx/wine"; \
		echo "  brew install gcenx/wine/game-porting-toolkit"; \
		exit 1; \
	}
	@command -v $(HEX2BIN) > /dev/null 2>&1 || { \
		echo "Error: '$(HEX2BIN)' not found."; \
		echo "Please install hex2bin via Homebrew:"; \
		echo "  brew install hex2bin"; \
		exit 1; \
	}
	@if [ ! -f "$(ZDS_DIR)/bin/ez80asm.exe" ]; then \
		echo "ZDS II toolchain not found at $(ZDS_DIR)."; \
		echo "Running 'make install-zds' to download and install it..."; \
		$(MAKE) install-zds; \
	fi

# 1. Fetch and unpack TRS-OS source tree from Daniel Paul Martin's site
fetch $(SRC_DIR)/TRSDOS.s:
	@echo "==> Fetching TRSDOS_7.zip from $(TRSDOS_URL)..."
	curl -s -L -o TRSDOS_7.zip "$(TRSDOS_URL)"
	@echo "==> Unpacking TRSDOS_7.zip..."
	unzip -q -o TRSDOS_7.zip
	rm -f TRSDOS_7.zip
	@echo "==> TRS-OS source files unpacked successfully."

# 1b. Apply patchset to fetched source tree
patch: $(PATCH_STAMP)

$(PATCH_STAMP): $(SRC_DIR)/TRSDOS.s $(PATCHES)
	@if [ -n "$(PATCHES)" ]; then \
		echo "==> Applying patchset from $(PATCH_DIR)..."; \
		for p in $(PATCHES); do \
			echo "    Applying $$p..."; \
			patch -p1 -N -r - < "$$p" || exit 1; \
		done; \
	fi
	@touch $@

# 2. Fetch ZDS II installer from Zilog
fetch-zds zds2_eZ80Acclaim!_5.3.5_23020901.zip:
	@echo "==> Fetching ZDS II installer from Zilog..."
	curl -s -L -X POST \
		-d "software_id=54&software_name=ZDS+II+-+eZ80Acclaim%21+version+5.3.5+with+RZK+and+TCP%2FIP+2.5.1+Object+Code&random_id=375" \
		"$(ZILOG_URL)" \
		-o zds2_eZ80Acclaim!_5.3.5_23020901.zip
	@echo "==> Downloaded zds2_eZ80Acclaim!_5.3.5_23020901.zip successfully."

# 3. Silently install ZDS II into Wine prefix
install-zds: check-wine zds2_eZ80Acclaim!_5.3.5_23020901.zip
	@echo "==> Installing ZDS II into Wine prefix silently..."
	mkdir -p /tmp/zds_setup
	unzip -q -o zds2_eZ80Acclaim!_5.3.5_23020901.zip -d /tmp/zds_setup
	$(WINE) /tmp/zds_setup/zds2_eZ80Acclaim!_5.3.5_23020901.exe /VERYSILENT /SUPPRESSMSGBOXES
	rm -rf /tmp/zds_setup zds2_eZ80Acclaim!_5.3.5_23020901.zip
	@echo "==> ZDS II installed into $(ZDS_DIR)."

check-wine:
	@command -v $(WINE) > /dev/null 2>&1 || { \
		echo "Error: '$(WINE)' not found. Install via:"; \
		echo "  brew tap gcenx/wine && brew install gcenx/wine/game-porting-toolkit"; \
		exit 1; \
	}

# 4. Generate portable linker command script from upstream template
$(LINKCMD): $(SRC_DIR)/debug/TRSDOS_Debug.linkcmd
	@echo "==> Generating portable $(LINKCMD)..."
	sed 's|"C:\\.*\\TRSDOS"|"TRSDOS"|' $< > $@

# 5. Assemble and link
$(TARGET_OBJ): $(SRC_DIR)/TRSDOS.s $(PATCH_STAMP)
	@echo "==> Assembling TRSDOS.s with eZ80asm.exe..."
	(cd $(SRC_DIR) && $(AS) $(ASFLAGS) TRSDOS.s)

$(TARGET_HEX) $(TARGET_LOD): $(TARGET_OBJ) $(LINKCMD)
	@echo "==> Linking $(TARGET_OBJ) with eZ80link.exe..."
	(cd $(SRC_DIR) && $(LD) @$(notdir $(LINKCMD)))
	@echo "==> Build successful: $(TARGET_HEX) generated."

# 5b. Generate flat binary for OSboot loader
$(TARGET_BIN): $(TARGET_HEX)
	@echo "==> Generating flat binary $(TARGET_BIN) for OSboot..."
	$(HEX2BIN) -s 000000 -p 00 "$<"
	@echo "==> Build successful: $(TARGET_BIN) ($$(wc -c < $(TARGET_BIN) | tr -d ' ') bytes) ready for OSboot."

# 6. Verify bit-for-bit against upstream release
verify: all
	@echo "==> Comparing built $(TARGET_HEX) against $(UPSTREAM_HEX)..."
	@if [ -n "$(PATCHES)" ] && [ -f "$(PATCH_STAMP)" ]; then \
		echo "Note: Patchset in $(PATCH_DIR) is applied; output includes custom modifications."; \
	fi
	@diff -u $(TARGET_HEX) $(UPSTREAM_HEX) && echo "==> Match! Output is 100% bit-for-bit identical to upstream." || true

# 7. Clean build artifacts
clean:
	rm -f $(TARGET_OBJ) $(TARGET_HEX) $(TARGET_LOD) $(TARGET_BIN) $(SRC_DIR)/TRSDOS.lst $(SRC_DIR)/TRSDOS.map $(LINKCMD)

# 8. Complete reset: remove build artifacts, source tree, and PDFs (leaves only Makefile, README.md, patches)
distclean: clean
	rm -rf $(SRC_DIR) $(GLOBAL_DIR) TRSDOS.pdf TRSDOS7_expanded_macros.pdf readme.txt
