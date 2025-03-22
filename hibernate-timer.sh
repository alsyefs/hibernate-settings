#!/bin/bash

# This script monitors lock status and hibernates after timeout
# Start this script as a systemd service

# Configurable variables
HIBERNATE_TIMEOUT=60  # 1 minutes (in seconds)
CHECK_INTERVAL=10      # Check status every 10 seconds
HIBERNATE_ONLY_ON_BATTERY=true  # Set to "false" if you want to hibernate regardless of power state
LOG_FILE="/tmp/hibernate-debug.log"  # Log file for debugging

# Enable debug logging
DEBUG=true

# Log function
log_debug() {
  if [ "$DEBUG" = "true" ]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
  fi
}

log_debug "Hibernate timer service started"

# Function to check if on battery power
check_on_battery() {
  # Try using the on_ac_power command if available
  if command -v on_ac_power &> /dev/null; then
    on_ac_power
    RESULT=$?
    # on_ac_power returns 0 if on AC, 1 if on battery
    # We want to return true (0) if on battery
    if [ $RESULT -eq 0 ]; then
      log_debug "Power check: On AC power"
      return 1  # On AC power
    else
      log_debug "Power check: On battery power"
      return 0  # On battery
    fi
  else
    # Fallback method: check if any power supply is online
    if grep -q "1" /sys/class/power_supply/*/online 2>/dev/null; then
      log_debug "Power check (fallback): On AC power"
      return 1  # On AC power
    else
      log_debug "Power check (fallback): On battery power"
      return 0  # On battery
    fi
  fi
}

# Function to check if screen is locked - multiple methods for better compatibility
check_screen_locked() {
  # Method 1: Standard loginctl method
  if loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p LockedHint 2>/dev/null | grep -q "yes"; then
    log_debug "Lock check (Method 1): Screen is locked"
    return 0  # Screen is locked
  fi

  # Method 2: KDE-specific method for Wayland
  # Check if kscreenlocker_greet is running
  if pgrep -f "kscreenlocker_greet" > /dev/null; then
    log_debug "Lock check (Method 2): Screen is locked (kscreenlocker_greet running)"
    return 0  # Screen is locked
  fi

  # Method 3: Check DBus property for KDE
  if command -v qdbus &> /dev/null; then
    if qdbus org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive 2>/dev/null | grep -q "true"; then
      log_debug "Lock check (Method 3): Screen is locked (via ScreenSaver DBus)"
      return 0  # Screen is locked
    fi
  fi

  # Method 4: Check for GNOME screensaver (for compatibility)
  if command -v dbus-send &> /dev/null; then
    if dbus-send --session --dest=org.gnome.ScreenSaver --type=method_call --print-reply --reply-timeout=1000 /org/gnome/ScreenSaver org.gnome.ScreenSaver.GetActive 2>/dev/null | grep -q "boolean true"; then
      log_debug "Lock check (Method 4): Screen is locked (GNOME ScreenSaver)"
      return 0  # Screen is locked
    fi
  fi

  log_debug "Lock check: Screen is not locked (all methods)"
  return 1  # Screen is not locked
}

# Main loop
while true; do
  # Check if screen is locked
  if check_screen_locked; then
    # Check power status if we're only hibernating on battery
    SHOULD_HIBERNATE=true

    if [ "$HIBERNATE_ONLY_ON_BATTERY" = "true" ]; then
      # Check if on battery power
      if ! check_on_battery; then
        SHOULD_HIBERNATE=false
        log_debug "Screen locked but on AC power, not hibernating"
        echo "Screen locked but on AC power, not hibernating"
      else
        log_debug "Screen locked and on battery, starting countdown to hibernation"
        echo "Screen locked and on battery, starting countdown to hibernation"
      fi
    else
      log_debug "Screen locked, starting countdown to hibernation"
      echo "Screen locked, starting countdown to hibernation"
    fi

    if [ "$SHOULD_HIBERNATE" = "true" ]; then
      # Wait for timeout period, checking every CHECK_INTERVAL seconds
      ELAPSED=0
      while [ $ELAPSED -lt $HIBERNATE_TIMEOUT ]; do
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))
        log_debug "Countdown: $ELAPSED / $HIBERNATE_TIMEOUT seconds elapsed"

        # Check if still locked
        if ! check_screen_locked; then
          log_debug "Screen was unlocked during countdown, aborting hibernation"
          echo "Screen was unlocked during countdown, aborting hibernation"
          SHOULD_HIBERNATE=false
          break
        fi

        # If battery-only mode is enabled, check if AC was connected
        if [ "$HIBERNATE_ONLY_ON_BATTERY" = "true" ]; then
          if ! check_on_battery; then
            log_debug "AC power connected during countdown, aborting hibernation"
            echo "AC power connected during countdown, aborting hibernation"
            SHOULD_HIBERNATE=false
            break
          fi
        fi
      done

      # If conditions still met after timeout, hibernate
      if [ "$SHOULD_HIBERNATE" = "true" ]; then
          log_debug "Screen still locked after timeout ($HIBERNATE_TIMEOUT seconds), hibernating"
          echo "Screen still locked after timeout, hibernating"

          # Try several methods to hibernate
          log_debug "Executing hibernation command as root..."
          /bin/systemctl hibernate &>> "$LOG_FILE" 2>&1

          HIBERNATE_RESULT=$?
          log_debug "Hibernate command returned: $HIBERNATE_RESULT"

          if [ $HIBERNATE_RESULT -ne 0 ]; then
              log_debug "Hibernate command failed, trying with dbus-send..."
              dbus-send --system --print-reply --dest=org.freedesktop.login1 \
                  /org/freedesktop/login1 org.freedesktop.login1.Manager.Hibernate boolean:true &>> "$LOG_FILE" 2>&1
              log_debug "dbus-send hibernate returned: $?"
          fi
      fi
    fi
  fi

  # Check every interval
  sleep $CHECK_INTERVAL
done
