#!/bin/bash

# This script monitors lock status and hibernates after timeout
# Start this script as a systemd service

# Configurable variables
HIBERNATE_TIMEOUT=60  # 1 minutes (in seconds)
CHECK_INTERVAL=10      # Check status every 10 seconds
HIBERNATE_ONLY_ON_BATTERY=true  # Set to "false" if you want to hibernate regardless of power state

# Function to check if on battery power
check_on_battery() {
  # Try using the on_ac_power command if available
  if command -v on_ac_power &> /dev/null; then
    on_ac_power
    RESULT=$?
    # on_ac_power returns 0 if on AC, 1 if on battery
    # We want to return true (0) if on battery
    if [ $RESULT -eq 0 ]; then
      return 1  # On AC power
    else
      return 0  # On battery
    fi
  else
    # Fallback method: check if any power supply is online
    if grep -q "1" /sys/class/power_supply/*/online 2>/dev/null; then
      return 1  # On AC power
    else
      return 0  # On battery
    fi
  fi
}

while true; do
  # Check if screen is locked
  if loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p LockedHint | grep -q "yes"; then
    # Check power status if we're only hibernating on battery
    SHOULD_HIBERNATE=true

    if [ "$HIBERNATE_ONLY_ON_BATTERY" = "true" ]; then
      # Check if on battery power
      if ! check_on_battery; then
        SHOULD_HIBERNATE=false
        echo "Screen locked but on AC power, not hibernating"
      else
        echo "Screen locked and on battery, starting countdown to hibernation"
      fi
    else
      echo "Screen locked, starting countdown to hibernation"
    fi

    if [ "$SHOULD_HIBERNATE" = "true" ]; then
      # Wait for timeout period, checking every CHECK_INTERVAL seconds
      ELAPSED=0
      while [ $ELAPSED -lt $HIBERNATE_TIMEOUT ]; do
        sleep $CHECK_INTERVAL
        ELAPSED=$((ELAPSED + CHECK_INTERVAL))

        # Check if still locked
        if ! loginctl show-session $(loginctl | grep $(whoami) | awk '{print $1}') -p LockedHint | grep -q "yes"; then
          echo "Screen was unlocked during countdown, aborting hibernation"
          SHOULD_HIBERNATE=false
          break
        fi

        # If battery-only mode is enabled, check if AC was connected
        if [ "$HIBERNATE_ONLY_ON_BATTERY" = "true" ]; then
          if ! check_on_battery; then
            echo "AC power connected during countdown, aborting hibernation"
            SHOULD_HIBERNATE=false
            break
          fi
        fi
      done

      # If conditions still met after timeout, hibernate
      if [ "$SHOULD_HIBERNATE" = "true" ]; then
        echo "Screen still locked after timeout, hibernating"
        systemctl hibernate
      fi
    fi
  fi

  # Check every 10 seconds
  sleep $CHECK_INTERVAL
done
