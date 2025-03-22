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

# Create polkit rules to allow hibernation without authentication
echo "Creating polkit rule for hibernation..."
mkdir -p /etc/polkit-1/rules.d/
cat > /etc/polkit-1/rules.d/99-hibernate-service.rules << EOFRULE
polkit.addRule(function(action, subject) {
    if (action.id == "org.freedesktop.login1.hibernate" ||
        action.id == "org.freedesktop.login1.hibernate-multiple-sessions" ||
        action.id == "org.freedesktop.login1.Manager.Hibernate") {
        return polkit.Result.YES;
    }
});
EOFRULE

# Create an additional polkit configuration file (more compatible with some systems)
echo "Creating additional polkit configuration..."
mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat > /etc/polkit-1/localauthority/50-local.d/hibernate.pkla << EOFPKLA
[Allow hibernation]
Identity=unix-user:*
Action=org.freedesktop.login1.hibernate;org.freedesktop.login1.hibernate-multiple-sessions
ResultActive=yes
ResultInactive=yes
ResultAny=yes
EOFPKLA

# Ensure log file directory exists and has correct permissions
echo "Setting up log file..."
touch /var/log/hibernate-timer.log
chmod 666 /var/log/hibernate-timer.log

# Install the desktop entry
echo "Installing desktop entry..."
cp hibernate-settings.desktop /usr/share/applications/

echo "Reloading systemd configuration..."
systemctl daemon-reload

# Restart polkit to apply the new rules
echo "Restarting polkit service..."
if [ -f "/usr/lib/systemd/system/polkit.service" ]; then
    systemctl restart polkit
fi

echo "Installation complete!"
echo "You can now launch Hibernate Settings from your application menu or run 'hibernate-settings-gui'"
