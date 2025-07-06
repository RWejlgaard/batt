# Batt - Cross-Platform Battery Monitor

A lightweight, cross-platform shell script for monitoring battery status with colored progress bars and detailed power information.

## Features

- **Cross-platform compatibility**: Works on macOS and Linux
- **Color-coded display**: Visual feedback with red (low), yellow (moderate), and green (high) battery levels
- **Progress bar visualization**: ASCII progress bar showing battery charge level
- **Detailed power metrics**: Current consumption, voltage, and time estimates
- **Multiple battery support**: Handles systems with multiple batteries (Linux)
- **Terminal-safe output**: Automatically detects terminal capabilities and adjusts accordingly

## Sample Output

```
BAT0 [########--------] 40% - Discharging 12.5W 2.3A Left 02:15
BAT1 [############----] 60% + Charging 8.2W 1.8A Full in 01:30
```

## Installation

### Option 1: Direct Download

1. Download the `batt` script to your desired location:
   ```bash
   wget https://raw.githubusercontent.com/your-repo/batt/main/batt
   # or
   curl -O https://raw.githubusercontent.com/your-repo/batt/main/batt
   ```

2. Make it executable:
   ```bash
   chmod +x batt
   ```

3. (Optional) Move to a directory in your PATH:
   ```bash
   sudo mv batt /usr/local/bin/
   ```

### Option 2: Clone Repository

```bash
git clone https://github.com/your-repo/batt.git
cd batt
chmod +x batt
# Optional: Add to PATH
sudo ln -s "$(pwd)/batt" /usr/local/bin/batt
```

## Usage

### Basic Usage

Simply run the script to display current battery status:

```bash
./batt
```

Or if installed in PATH:

```bash
batt
```

### Integration Examples

#### Add to Shell Prompt

Add to your `.bashrc` or `.zshrc` for always-visible battery status:

```bash
# Add battery info to PS1
export PS1='$(batt) '"$PS1"
```

#### Status Bar Integration

For window managers like i3, dwm, or status bars:

```bash
# i3status configuration
bar {
    status_command while date +'%Y-%m-%d %H:%M:%S'; do echo "$(batt) | $(date)"; sleep 1; done
}
```

#### Tmux Integration

Add to your tmux status line:

```bash
# In ~/.tmux.conf
set -g status-right '#(batt) | %Y-%m-%d %H:%M'
```

#### Scheduled Monitoring

Monitor battery levels with cron:

```bash
# Add to crontab for low battery alerts
*/5 * * * * if [ $(batt | grep -o '[0-9]*%' | tr -d '%') -lt 15 ]; then notify-send "Low Battery"; fi
```

## Technical Details

### How It Works

#### macOS Implementation
- Uses `pmset -g batt` to query battery information
- Parses output to extract capacity, charging status, and time remaining
- Handles various charging states: charging, discharging, charged, AC attached

#### Linux Implementation
- Reads from `/sys/class/power_supply/BAT*` directories
- Supports multiple batteries automatically
- Calculates power consumption and time estimates from:
  - `capacity`: Battery charge percentage
  - `status`: Charging state
  - `power_now`: Current power consumption (µW)
  - `current_now`: Current draw (µA)
  - `voltage_now`: Current voltage (µV)
  - `energy_now/energy_full`: Current/full energy capacity (µWh)

### Output Format

The script outputs information in this format:

```
BATTERY_NAME [PROGRESS_BAR] PERCENTAGE% STATUS POWER CURRENT TIME_INFO
```

Where:
- **BATTERY_NAME**: Battery identifier (BAT0, BAT1, etc.)
- **PROGRESS_BAR**: 20-character ASCII bar showing charge level
- **PERCENTAGE**: Current charge percentage with color coding
- **STATUS**: Charging state with symbols:
  - `+` Charging (blue)
  - `-` Discharging (color-coded by level)
  - `=` Full (green)
  - `?` Unknown (yellow)
- **POWER**: Current power consumption in watts
- **CURRENT**: Current draw in amperes
- **TIME_INFO**: Time remaining or time to full charge

### Color Coding

- **Red**: ≤ 10% battery (critical)
- **Yellow**: 11-25% battery (low)
- **Green**: > 25% battery (normal)
- **Blue**: Charging status

## Requirements

### macOS
- Built-in `pmset` command (available on all macOS systems)
- Shell with POSIX compliance (`/bin/sh`)

### Linux
- Access to `/sys/class/power_supply/` directory
- `bc` calculator for power calculations
- Shell with POSIX compliance (`/bin/sh`)

### Install Linux Dependencies

On Ubuntu/Debian:
```bash
sudo apt-get install bc
```

On CentOS/RHEL/Fedora:
```bash
sudo yum install bc
# or
sudo dnf install bc
```

## Troubleshooting

### "No battery found"
- **macOS**: Ensure you're running on a MacBook or device with battery
- **Linux**: Check that `/sys/class/power_supply/BAT*` directories exist

### No colors displayed
- Ensure your terminal supports ANSI colors
- Check that `$TERM` environment variable is set correctly
- Try running in a different terminal emulator

### Incorrect time calculations
- Time estimates are calculated based on current power consumption
- Estimates become more accurate over time as power usage stabilizes
- May show `--:--` when power consumption data is unavailable

### Permission denied
- Ensure the script has execute permissions: `chmod +x batt`
- On Linux, ensure access to `/sys/class/power_supply/` (usually readable by all users)

## Contributing

Contributions are welcome! Please feel free to:
- Report bugs
- Suggest features
- Submit pull requests
- Improve documentation

## License

This project is released under the MIT License. See LICENSE file for details.

## Compatibility

### Tested Platforms
- macOS 10.14+
- Ubuntu 18.04+
- Debian 9+
- CentOS 7+
- Arch Linux
- Fedora 28+

### Shell Compatibility
- bash
- zsh
- dash
- sh (POSIX)

The script is designed to be POSIX-compliant and should work with any POSIX-compatible shell.