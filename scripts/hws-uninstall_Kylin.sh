#!/bin/sh

LOGFILE=hws_install.log

SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"
MODULE_NAME=HwsCapture
MODULE_INSTALL_DIR=/usr/local/share/HWS

KVER=`uname -r`
KERNEL_BASE="/lib/modules/$KVER"
KO_DST="$KERNEL_BASE/updates/dkms/$MODULE_NAME.ko"
KO_EXTRA="$KERNEL_BASE/extra/$MODULE_NAME.ko"
KO_OPT="/opt/HWS/ko/$KVER/$MODULE_NAME.ko"

DEPMOD=`which depmod 2>/dev/null`

echo_string ()
{
    echo "$1" | tee -a $LOGFILE
}

echo_string_nonewline ()
{
    echo -n "$1" | tee -a $LOGFILE
}

NO_REBOOT_PROMPT=""
while getopts "n" flag ; do
   case "$flag" in
      n)NO_REBOOT_PROMPT="YES";;
   esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "Root privileges required. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

if command -v systemctl >/dev/null 2>&1; then
    systemctl stop hws.service >> $LOGFILE 2>&1 || true
    systemctl disable hws.service >> $LOGFILE 2>&1 || true
    rm -f /etc/systemd/system/hws.service >> $LOGFILE 2>&1 || true
    systemctl daemon-reload >> $LOGFILE 2>&1 || true
fi

if lsmod | grep -q "^$MODULE_NAME\b"; then
    rmmod $MODULE_NAME >> $LOGFILE 2>&1 || true
fi

remove_one()
{
    f="$1"
    if [ -e "$f" ]; then
        echo_string_nonewline "Removing $f ... "
        rm -f "$f" >> $LOGFILE 2>&1
        if [ $? -ne 0 ]; then
            echo_string "Permission denied (policy may block). Skipped."
        else
            echo_string "Done."
        fi
    fi
}

remove_one "$KO_DST"
remove_one "$KO_EXTRA"
remove_one "$KO_OPT"

if [ -n "$DEPMOD" ]; then
    echo_string_nonewline "Re-generating modules.dep and map files ... "
    $DEPMOD -a >> $LOGFILE 2>&1
    if [ $? -ne 0 ]; then
        echo_string "depmod failed (policy may block rename). Skipped."
    else
        echo_string "Done."
    fi
fi

if [ -d "$MODULE_INSTALL_DIR" ]; then
    echo_string_nonewline "Removing installed files ... "
    rm -rf "$MODULE_INSTALL_DIR" >> $LOGFILE 2>&1
    if [ $? -ne 0 ]; then
        echo_string "Permission denied (policy may block). Skipped."
    else
        echo_string "Done."
    fi
fi

rm -f /usr/bin/hws-repair.sh /usr/bin/hws-uninstall.sh >> $LOGFILE 2>&1 || true

MODULE_LOADED=`lsmod | grep "^$MODULE_NAME\b"`
echo_string ""
if [ -z "$MODULE_LOADED" -o x"$NO_REBOOT_PROMPT" = x"YES" ]; then
    echo_string "Uninstall Successfully!"
else
    echo_string "Uninstall Successfully!"
    echo_string "!!!!Reboot is needed to unload module!"
    echo_string_nonewline "Do you wish to reboot now (Y/N) [N]: "
    read cont

    if [ "$cont" != "YES" -a "$cont" != "yes" -a \
        "$cont" != "Y" -a "$cont" != "y" ] ; then
        echo_string "Reboot canceled! You should reboot your system manually later."
    else
        reboot
    fi
fi

echo_string ""
