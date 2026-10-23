# Build libcli for coil-cli FFI.

ARTIFACT_DIR ?= .

CC ?= cc
CFLAGS ?= -O2 -Wall -Wextra -std=c11

UNAME_S := $(shell uname -s 2>/dev/null)

ifdef MSYSTEM
  PLATFORM := windows
else ifeq ($(OS),Windows_NT)
  PLATFORM := windows
else ifeq ($(UNAME_S),Darwin)
  PLATFORM := macos
else
  PLATFORM := linux
  ifneq ($(shell $(CC) -dumpmachine 2>/dev/null | grep -o musl),)
    PLATFORM := linux-musl
  endif
endif

ifeq ($(PLATFORM),macos)
  LIB := libcli.dylib
  CFLAGS_PIC := -fPIC
  LDFLAGS_SHLIB := -dynamiclib
  SMOKE_RPATH :=
else ifeq ($(PLATFORM),windows)
  LIB := libcli.dll
  CFLAGS_PIC :=
  LDFLAGS_SHLIB := -shared
  SMOKE_RPATH :=
else
  LIB := libcli.so
  CFLAGS_PIC := -fPIC
  LDFLAGS_SHLIB := -shared
  SMOKE_RPATH := -Wl,-rpath,'$$ORIGIN'
endif

LIB_PATH := $(ARTIFACT_DIR)/$(LIB)

.PHONY: all artifact clean smoke print-artifact print-platform

all: artifact

artifact: $(LIB_PATH)

print-platform:
	@echo $(PLATFORM)

print-artifact:
	@echo $(LIB_PATH)

cli.o: cli.c cli.h
	$(CC) $(CFLAGS) $(CFLAGS_PIC) -c -o $@ cli.c

$(LIB_PATH): cli.o
	$(CC) $(LDFLAGS_SHLIB) -o $@ $^

smoke.bin: smoke.c cli.h $(LIB_PATH)
	$(CC) $(CFLAGS) -o $@ smoke.c -L$(ARTIFACT_DIR) -lcli $(SMOKE_RPATH)

smoke: smoke.bin
	./smoke.bin

clean:
	rm -f cli.o smoke.bin smoke \
		$(ARTIFACT_DIR)/libcli.so \
		$(ARTIFACT_DIR)/libcli.dylib \
		$(ARTIFACT_DIR)/libcli.dll \
		$(ARTIFACT_DIR)/cli.dll
