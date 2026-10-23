# coil-cli — run package tests and the format check.
#
# Targets:
#   make test   — coil test harness (needs `coil` on PATH)
#   make fmt    — check formatting of src/ and tests/

.PHONY: all test fmt

COIL ?= coil
# Extra module roots for `make test` (CI passes the coil-stdlib checkout).
COIL_ROOTS ?=

all: test

test:
	$(COIL) test $(COIL_ROOTS)

fmt:
	$(COIL) fmt --check src tests
