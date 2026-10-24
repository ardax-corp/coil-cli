# coil-cli — run package tests and the format check.
#
# Targets:
#   make test   — coil test harness (needs `coil` on PATH)
#   make fmt    — check formatting of src/, tests/ and examples/
#   make examples — compile every example (catches API drift)

.PHONY: all test fmt examples

COIL ?= coil
# Extra module roots for `make test` (CI passes the coil-stdlib checkout).
COIL_ROOTS ?=
# The prompt tests read and write scratch files.
COIL_TEST_FLAGS ?= --allow-read --allow-write

all: test

test:
	$(COIL) test $(COIL_TEST_FLAGS) $(COIL_ROOTS)

fmt:
	$(COIL) fmt --check src tests examples

EXAMPLES_OUT ?= .examples

examples:
	mkdir -p $(EXAMPLES_OUT)
	for f in examples/*.hy; do \
		$(COIL) compile --allow-env --allow-exit $(COIL_ROOTS) --root src -o $(EXAMPLES_OUT)/$$(basename $$f .hy).hyc $$f || exit 1; \
	done
