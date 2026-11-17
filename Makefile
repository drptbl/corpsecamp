# The WoW: Forever client's AddOns folder; `make addon-link WOW_ADDONS=<dir>` overrides it.
WOW_ADDONS ?= /Applications/World of Warcraft/_forever_/Interface/AddOns

# Versions come from the TOC files (`.. Version:` avoids a literal hash, which make reads as a comment).
VERSION := $(shell awk '/^.. Version:/ {print $$3}' CorpseCamp/CorpseCamp.toc)
PROBE_VERSION := $(shell awk '/^.. Version:/ {print $$3}' CampProbe/CampProbe.toc)

.PHONY: addon-link probe-link test dist

# Symlinks an addon folder of this checkout into the client's AddOns folder, so a `/reload`
# picks up every edit (a new addon or a TOC change needs a full client relaunch). Refuses
# to replace a real directory: an installed copy must be moved away by hand.
define link_addon
	@if [ ! -d "$(WOW_ADDONS)" ]; then \
		echo "$(1): $(WOW_ADDONS) is not a directory (set WOW_ADDONS=<AddOns dir>)"; \
		exit 1; \
	fi
	@if [ -e "$(WOW_ADDONS)/$(1)" ] && [ ! -L "$(WOW_ADDONS)/$(1)" ]; then \
		echo "$(1): $(WOW_ADDONS)/$(1) exists and is not a symlink; move it away first"; \
		exit 1; \
	fi
	ln -sfn "$(CURDIR)/$(1)" "$(WOW_ADDONS)/$(1)"
	@echo "$(WOW_ADDONS)/$(1) -> $(CURDIR)/$(1)"
endef

addon-link:
	$(call link_addon,CorpseCamp)

# The optional diagnostic addon (README § Optional: probe).
probe-link:
	$(call link_addon,CampProbe)

test:
	@command -v luajit >/dev/null 2>&1 || { echo "luajit not found — brew install luajit"; exit 1; }
	luajit tests/test_core.lua
	luajit tests/test_glue.lua

# Release zips: each extracts to its addon folder, ready for Interface/AddOns.
dist: test
	rm -rf dist && mkdir -p dist
	zip -rqX "dist/CorpseCamp-$(VERSION).zip" CorpseCamp -x '*.DS_Store'
	zip -rqX "dist/CampProbe-$(PROBE_VERSION).zip" CampProbe -x '*.DS_Store'
	@ls -l dist
