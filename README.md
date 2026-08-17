# Batt - Assembly Battery Monitor

A lightweight battery monitoring tool written in pure x86-64 assembly for Linux systems. Displays real-time battery information with color-coded output and progress bars.

## Features

- **Visual Progress Bar**: 20-character battery level indicator with color coding
- **Color-coded Output**: Red (≤10%), Yellow (≤25%), Green (>25%) — only when writing to a terminal
- **Multiple Display Modes**: Show everything, or any combination of percentage, watts, amps and time
- **Real-time Metrics**: Current charge, voltage, power consumption, and time remaining
- **Status Indicators**: Charging (+), Discharging (-), Full (=), Unknown (?)
- **Time Estimation**: Shows charging time or discharge time remaining
- **Automatic Battery Detection**: Finds every `BAT*` device, no hardcoded paths

## Installation

### Prerequisites
- Linux system with a `/sys/class/power_supply/` battery interface
- NASM assembler
- GNU linker (ld)

### Build from Source
```bash
make
```

### Install System-wide (Optional)
```bash
sudo make install
```

### Clean Build Files
```bash
make clean
```

## Usage

### Basic Usage
Display all battery information:
```bash
./batt
```

Example output:
```
BAT1 [##########----------]  50% - 8.58W 0.78A Left 03:12
```

### Command Line Options

```bash
./batt [OPTIONS]
```

| Option | Description |
|--------|-------------|
| `-w, --watts` | Show only wattage information |
| `-p, --percentage` | Show only percentage information |
| `-t, --time` | Show only time remaining information |
| `-a, --amps` | Show only amperage information |
| `-h, --help` | Show help message |

Options can be combined; each requested field is printed on its own line.

### Examples

Show only battery percentage:
```bash
./batt -p
# Output:  75%
```

Show only power consumption:
```bash
./batt -w
# Output: 12.45W
```

Show time remaining:
```bash
./batt -t
# Output: Left 03:12
```

## How It Works

### High-Level Architecture

The program is structured as a single-pass system that:

1. **Argument Parsing**: Processes command line flags using string comparison
2. **Battery Discovery**: Scans `/sys/class/power_supply/` for battery devices
3. **Data Collection**: Reads battery metrics from Linux sysfs interface
4. **Calculation**: Computes power consumption and time estimates
5. **Display**: Formats the whole line in memory and writes it with one syscall

### Battery Discovery

Every `BAT*` entry under `/sys/class/power_supply/` is reported, in order. If there
is no `BAT*` entry, the first device exposing a `capacity` file is used instead, which
covers machines that name their battery differently.

### Battery Data Sources

The tool reads from standard Linux power supply interfaces:

- `capacity` - Battery percentage (0-100)
- `status` - Charging status (Charging/Discharging/Full)
- `current_now` - Current draw in microamps
- `voltage_now` - Voltage in microvolts
- `power_now` - Power draw in microwatts
- `charge_now` / `charge_full` - Charge in microamp-hours
- `energy_now` / `energy_full` - Energy in microwatt-hours

Batteries report either charge (`charge_*` + `current_now`) or energy (`energy_*` +
`power_now`); both are handled, and whichever of power/current is missing is derived
from the other.

### Key Calculations

**Power** (when `power_now` is absent):
```
power (µW) = (current_now × voltage_now) ÷ 1,000,000
```

**Current** (when `current_now` is absent):
```
current (µA) = (power_now × 1,000,000) ÷ voltage_now
```

**Time Remaining** (rate is `current_now` for charge-based batteries, `power_now` for energy-based ones):
- **Discharging**: `time = (now × 60) ÷ rate` minutes
- **Charging**: `time = ((full - now) × 60) ÷ rate` minutes

**Progress Bar**:
- 20 characters total
- Filled bars: `(capacity × 20) ÷ 100`
- Color coding based on percentage thresholds

### Assembly Implementation Details

- **System Calls**: Direct Linux syscalls only (`open`, `read`, `write`, `close`, `getdents64`, `ioctl`)
- **No libc**: Statically linked, no dynamic loader at startup
- **Memory Management**: Static buffers for file operations and string processing
- **Number Conversion**: Custom ASCII-to-integer and integer-to-ASCII routines
- **String Operations**: Hand-coded string comparison and length calculation
- **Color Output**: ANSI escape sequences, suppressed when stdout is not a terminal

## Requirements

- Linux kernel with sysfs power supply interface
- x86-64 architecture
- Terminal with ANSI color support (optional)

## Technical Specifications

- **Language**: x86-64 Assembly (Intel syntax)
- **Assembler**: NASM
- **Target**: Linux ELF64
- **Dependencies**: None (uses only Linux syscalls)
- **Memory Usage**: ~2KB static buffers
- **Performance**: Sub-millisecond execution time

## Troubleshooting

**"No battery found" error**:
- Verify a battery exists: `ls /sys/class/power_supply/`
- Ensure proper file permissions

**Permission denied**:
- Battery files should be readable by all users
- No special privileges required

**Incorrect readings**:
- Some laptops may use different power supply interfaces
- Check `lspci` for power management controllers

## License

This project is open source. See the source code for implementation details.
