# coil-cli — build the FFI artifact and run package tests.
#
# Targets:
#   make / make native  — build native/libcli.{so,dylib,dll}
#   make smoke          — C ABI smoke test (after native)
#   make test           — coil language harness (needs `coil` on PATH)
#   make clean          — remove build products

.PHONY: all native smoke test clean dist

COIL ?= coil
# Extra module roots for `make test` (CI passes the coil-stdlib checkout).
COIL_ROOTS ?=

all: native

native:
	$(MAKE) -C native artifact

smoke: native
	$(MAKE) -C native smoke

# SHA-256 of a built native library ($(1) = path without extension). coil's
# dload gate needs `--dload-pin STEM=SHA256` (or `--dload-trusted STEM`).
lib_sha = $(shell lib=$(1).so; [ -f $(1).dylib ] && lib=$(1).dylib; [ -f $(1).dll ] && lib=$(1).dll; \
	if command -v sha256sum >/dev/null 2>&1; then sha256sum "$$lib"; else shasum -a 256 "$$lib"; fi 2>/dev/null | awk '{print $$1}')

test: native
	$(COIL) test --allow-dload cli --dload-pin cli=$(call lib_sha,native/libcli) --ffi-search-path native $(COIL_ROOTS)

clean:
	$(MAKE) -C native clean

dist: native
	@$(MAKE) -C native print-artifact
