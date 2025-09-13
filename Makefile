# Makefile for bl (Assembly backlight controller)

# Variables
ASM = nasm
LD = ld
ASMFLAGS = -f elf64
LDFLAGS = -lc -dynamic-linker /lib64/ld-linux-x86-64.so.2

# Target executable
TARGET = batt

# Source files
SRC = batt.asm
OBJ = batt.o

# Default target
all: $(TARGET)

# Build the executable
$(TARGET): $(OBJ)
	$(LD) -o $@ $< $(LDFLAGS)

# Assemble the source
$(OBJ): $(SRC)
	$(ASM) $(ASMFLAGS) -o $@ $<

# Clean build artifacts
clean:
	rm -f $(OBJ) $(TARGET)

# Install the executable (optional)
install: $(TARGET)
	install -m 755 $(TARGET) /usr/local/bin/

# Uninstall
uninstall:
	rm -f /usr/local/bin/$(TARGET)

# Phony targets
.PHONY: all clean install uninstall
