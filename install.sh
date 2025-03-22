#!/bin/bash

# Display info
echo "Installing Hibernate Settings GUI..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
  echo "Please run as root"
  exit 1
fi

# Check for dependencies
echo "Checking dependencies..."
DEPS_MISSING=0

# Check for Python
if ! command -v python3 &> /dev/null; then
    echo "Python 3 is not installed. Please install it first."
    DEPS_MISSING=1
fi

# Check for PyQt5
python3 -c "import PyQt5" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "PyQt5 is not installed. Please install python-pyqt5 package."
    DEPS_MISSING=1
fi

if [ $DEPS_MISSING -eq 1 ]; then
    echo "Please install missing dependencies and try again."
    echo "For Arch Linux: sudo pacman -S python python-pyqt5"
    echo "For Ubuntu/Debian: sudo apt install python3 python3-pyqt5"
    exit 1
fi

# Install helper scripts if they don't exist
echo "Installing scripts..."

# Copy the hibernate timer script
cp hibernate-timer.sh /usr/local/bin/
chmod +x /usr/local/bin/hibernate-timer.sh

# Copy the GUI application
cp hibernate-settings-gui /usr/local/bin/
chmod +x /usr/local/bin/hibernate-settings-gui

# Create systemd service if it doesn't exist
if [ ! -f "/etc/systemd/system/hibernate-timer.service" ]; then
    echo "Creating systemd service..."
    cat > /etc/systemd/system/hibernate-timer.service << EOFSERVICE
[Unit]
Description=Screen lock hibernation service
After=graphical.target

[Service]
ExecStart=/usr/local/bin/hibernate-timer.sh
Restart=always
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=graphical.target
EOFSERVICE
fi

# Install the desktop entry
echo "Installing desktop entry..."
cp hibernate-settings.desktop /usr/share/applications/

echo "Reloading systemd configuration..."
systemctl daemon-reload

echo "Installation complete!"
echo "You can now launch Hibernate Settings from your application menu or run 'hibernate-settings-gui'"
