#!/bin/sh

LOGFILE=hws_install.log

if [ -h "$0" ]; then
    SCRIPT_PATH=`readlink "$0" | xargs dirname`
else
    SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)"
fi

HWS_TOP_DIR=$SCRIPT_PATH/..
SRC_DIR=$HWS_TOP_DIR/src
MODULE_NAME=HwsCapture
MODULE_INSTALL_DIR=/usr/local/share/HWS
MODULE_BUILD_DIR="`pwd`/hws_build"

ARCH=`uname -m | sed -e 's/i.86/i386/'`
case $ARCH in
    i386) ARCH_BITS=32 ;;
    arm*) ARCH_BITS=arm ;;
    aarch64) ARCH_BITS=aarch64 ;;
    *) ARCH_BITS=64 ;;
esac

KVER=`uname -r`
KERNEL_BASE="/lib/modules/$KVER"
KERNEL_BUILD="$KERNEL_BASE/build"

KO_DST_DIR="$KERNEL_BASE/updates/dkms"
KO_DST="$KO_DST_DIR/$MODULE_NAME.ko"
KO_OPT_DIR="/opt/HWS/ko/$KVER"
KO_OPT="$KO_OPT_DIR/$MODULE_NAME.ko"

DEPMOD=`which depmod 2>/dev/null`
MODPROBE=`which modprobe 2>/dev/null`
INSMOD=`which insmod 2>/dev/null`

echo_string ()
{
    echo "$1" | tee -a $LOGFILE
}

echo_string_nonewline ()
{
    echo -n "$1" | tee -a $LOGFILE
}

error_exit ()
{
    echo ""
    echo "Please check $LOGFILE for more details."
    echo "If you are experiencing difficulty with this installation"
    echo "please contact alex.liu@longtimetech.com"
    exit 1
}

load_dependencies ()
{
    [ -n "$MODPROBE" ] || return 0
    $MODPROBE snd >> $LOGFILE 2>&1 || true
    $MODPROBE snd_pcm >> $LOGFILE 2>&1 || true
    $MODPROBE videobuf2_common >> $LOGFILE 2>&1 || true
    $MODPROBE videobuf2_vmalloc >> $LOGFILE 2>&1 || true
    $MODPROBE videobuf2_v4l2 >> $LOGFILE 2>&1 || true
    $MODPROBE videodev >> $LOGFILE 2>&1 || true
}

enable_autoload ()
{
    echo_string_nonewline "Enabling auto-load at boot (systemd) ... "

    TMP_SERVICE=/tmp/hws.service.$$
    cat > "$TMP_SERVICE" <<'EOF'
[Unit]
Description=Load HwsCapture kernel module
After=multi-user.target systemd-udev-settle.service systemd-modules-load.service
Wants=multi-user.target systemd-udev-settle.service systemd-modules-load.service

[Service]
Type=oneshot
ExecStartPre=/bin/sleep 2
ExecStart=/bin/sh -c '/sbin/modprobe snd 2>/dev/null || true; /sbin/modprobe snd_pcm 2>/dev/null || true; /sbin/modprobe videobuf2_common 2>/dev/null || true; /sbin/modprobe videobuf2_vmalloc 2>/dev/null || true; /sbin/modprobe videobuf2_v4l2 2>/dev/null || true; /sbin/modprobe videodev 2>/dev/null || true; /sbin/lsmod | /bin/grep -q "^HwsCapture" && exit 0; KVER=$(/bin/uname -r); if [ -f /lib/modules/$KVER/updates/dkms/HwsCapture.ko ]; then exec /sbin/insmod /lib/modules/$KVER/updates/dkms/HwsCapture.ko; fi; if [ -f /opt/HWS/ko/$KVER/HwsCapture.ko ]; then exec /sbin/insmod /opt/HWS/ko/$KVER/HwsCapture.ko; fi; exit 1'
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF

    install -m 644 "$TMP_SERVICE" /etc/systemd/system/hws.service >> $LOGFILE 2>&1
    RET=$?
    rm -f "$TMP_SERVICE"

    if [ $RET -ne 0 ]; then
        echo_string ""
        echo_string "ERROR: Failed to create /etc/systemd/system/hws.service"
        error_exit
    fi

    if command -v systemctl >/dev/null 2>&1; then
        systemctl daemon-reload >> $LOGFILE 2>&1 || true
        systemctl enable hws.service >> $LOGFILE 2>&1 || true
    fi

    echo_string "Done."
}

build_prepare ()
{
    if [ -d $MODULE_BUILD_DIR ]; then
        echo_string "Build directory: $MODULE_BUILD_DIR already exists."
        echo_string_nonewline "Do you wish to remove $MODULE_BUILD_DIR (Y/N) [N]: "
        read cont

        if [ "$cont" != "YES" -a "$cont" != "yes" -a \
            "$cont" != "Y" -a "$cont" != "y" ] ; then
            echo
            echo "Cancelling installation, $MODULE_BUILD_DIR unmodified."
            exit
        fi

        echo_string_nonewline "Removing directory $MODULE_BUILD_DIR ... "
        rm -rvf $MODULE_BUILD_DIR >> $LOGFILE 2>&1
        RET=$?
        if [ $RET -ne 0 ]; then
            echo_string ""
            echo_string "ERROR: Failed to remove directory:"
            echo_string "   $MODULE_BUILD_DIR"
            echo_string "You should remove it manually."
            error_exit
        fi
        echo_string "Done."
    fi

    echo_string_nonewline "Creating build directory $MODULE_BUILD_DIR ... "
    mkdir -p $MODULE_BUILD_DIR >> $LOGFILE 2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
        echo_string ""
        echo_string "ERROR: Failed to create build directory $MODULE_BUILD_DIR"
        error_exit
    fi
    echo_string "Done."

    echo_string_nonewline "Copying driver source into $MODULE_BUILD_DIR ... "
    cp -avf $SRC_DIR/. $MODULE_BUILD_DIR >> $LOGFILE 2>&1
    RET=$?
    if [ $RET -ne 0 ]; then
        echo_string ""
        echo_string "ERROR: Failed to copy driver source into $MODULE_BUILD_DIR"
        error_exit
    fi
    echo_string "Done."
}

build_module ()
{
    echo_string_nonewline "Building module for kernel `uname -r` ... "
    make -C $MODULE_BUILD_DIR -j4 >> $LOGFILE 2>&1
    RET=$?
    if [ $RET -ne 0 ] ; then
        echo_string ""
        echo_string "ERROR: Failed to build module!"
        error_exit
    fi
    if [ ! -f "$MODULE_BUILD_DIR/$MODULE_NAME.ko" ]; then
        echo_string ""
        echo_string "ERROR: Build OK but KO not found: $MODULE_BUILD_DIR/$MODULE_NAME.ko"
        error_exit
    fi
    echo_string "Done."
}

build_clean ()
{
    if [ -d $MODULE_BUILD_DIR ]; then
        echo_string_nonewline "Removing build directory $MODULE_BUILD_DIR ... "
        rm -rvf $MODULE_BUILD_DIR >> $LOGFILE 2>&1
        RET=$?
        if [ $RET -ne 0 ]; then
            echo_string "Warning: Failed to remove build directory:"
            echo_string "   $MODULE_BUILD_DIR"
            echo_string "You should remove it manually."
        fi
        echo_string "Done."
    fi
}

install_module ()
{
    echo_string_nonewline "Installing module (kylin-safe) ... "

    mkdir -p "$KO_DST_DIR" >> $LOGFILE 2>&1 || true
    mkdir -p "$KO_OPT_DIR" >> $LOGFILE 2>&1 || true

    install -m 644 "$MODULE_BUILD_DIR/$MODULE_NAME.ko" "$KO_DST" >> $LOGFILE 2>&1 || true
    install -m 644 "$MODULE_BUILD_DIR/$MODULE_NAME.ko" "$KO_OPT" >> $LOGFILE 2>&1 || true

    if [ -f "$KO_DST" ]; then
        echo_string ""
        echo_string "Installed KO to $KO_DST"
    fi
    if [ -f "$KO_OPT" ]; then
        echo_string "Installed KO to $KO_OPT"
    fi

    if [ ! -f "$KO_DST" -a ! -f "$KO_OPT" ]; then
        echo_string ""
        echo_string "ERROR: KO was not installed to $KO_DST nor $KO_OPT"
        error_exit
    fi

    if [ ! -d $MODULE_INSTALL_DIR ]; then
        mkdir -p $MODULE_INSTALL_DIR >> $LOGFILE 2>&1 || true
    fi

    if [ ! -d "$MODULE_INSTALL_DIR/src" ]; then
        cp -rvf $HWS_TOP_DIR/src $MODULE_INSTALL_DIR >> $LOGFILE 2>&1 || \
            echo_string "Warning: copy src blocked by policy. Skipped."
    else
        echo_string "Info: $MODULE_INSTALL_DIR/src exists, skip overwrite (kylin-safe)."
    fi

    if [ ! -d "$MODULE_INSTALL_DIR/scripts" ]; then
        cp -rvf $HWS_TOP_DIR/scripts $MODULE_INSTALL_DIR >> $LOGFILE 2>&1 || \
            echo_string "Warning: copy scripts blocked by policy. Skipped."
    else
        echo_string "Info: $MODULE_INSTALL_DIR/scripts exists, skip overwrite (kylin-safe)."
    fi

    ln -sf $MODULE_INSTALL_DIR/scripts/hws-repair.sh /usr/bin/ >> $LOGFILE 2>&1 || true
    ln -sf $MODULE_INSTALL_DIR/scripts/hws-uninstall.sh /usr/bin/ >> $LOGFILE 2>&1 || true

    if [ -n "$DEPMOD" ]; then
        $DEPMOD -a >> $LOGFILE 2>&1
        RET=$?
        if [ $RET -ne 0 ] ; then
            echo_string "Warning: depmod failed (kysec may block rename). Will continue."
        fi
    fi

    echo_string "Done."
}

SECOND=""
while getopts "s" flag ; do
   case "$flag" in
      s)SECOND="YES";;
   esac
done

if [ "YES" != "$SECOND" ] ; then
echo "==================================================="
echo "      HWS Linux Driver Installer"
echo "==================================================="
echo ""
fi

if [ "$(id -u)" -ne 0 ]; then
    echo "Root privileges required. Re-running with sudo..."
    exec sudo "$0" "$@"
fi

echo -n "" > $LOGFILE

echo_string_nonewline "Checking for required tools ... "
MISSING_TOOLS=""
REQUIRED_TOOLS="make gcc ld modprobe insmod install"
for tool in $REQUIRED_TOOLS ; do
    command -v $tool >/dev/null 2>&1
    RET=$?
    if [ $RET -ne 0 ] ; then
        MISSING_TOOLS="$MISSING_TOOLS $tool"
    fi
done

if [ -n "$MISSING_TOOLS" ]; then
    echo_string ""
    echo_string ""
    echo_string "Your system has one or more system tools missing which are"
    echo_string "required to compile and load the HWS Linux driver."
    echo_string ""
    echo_string "Required tools: $MISSING_TOOLS"
    error_exit
else
    echo_string "Done."
fi

echo_string_nonewline "Checking for kernel headers ... "
if [ ! -d $KERNEL_BUILD ]; then
    echo_string ""
    echo_string ""
    echo_string "Your system is missing kernel headers which"
    echo_string "is required to build and load the HWS Linux driver."
    echo_string ""
    echo_string "Required: /lib/modules/`uname -r`/build"
    error_exit
else
    echo_string "Done."
fi

echo_string_nonewline "Checking for previous installation ... "
MODULE_FILE=`find /lib/modules/$KVER -maxdepth 4 -iname "$MODULE_NAME.ko" 2>/dev/null`

if [ -n "$MODULE_FILE" -o -e "$MODULE_INSTALL_DIR" -o -e "$KO_OPT" ]; then
    echo_string "Found"
    echo_string "Removing previous installation..."
    $SCRIPT_PATH/hws-uninstall.sh -n >> $LOGFILE 2>&1 || true
else
    echo_string "None"
fi

echo_string "Beginning install, please wait... "

build_prepare
build_module
install_module
build_clean
enable_autoload

echo_string_nonewline "Loading dependencies (ALSA/VB2) ... "
load_dependencies
echo_string "Done."

KO_TO_LOAD=""
if [ -f "$KO_DST" ]; then
    KO_TO_LOAD="$KO_DST"
elif [ -f "$KO_OPT" ]; then
    KO_TO_LOAD="$KO_OPT"
fi

if lsmod | grep -q "^$MODULE_NAME\b"; then
    echo_string "Info: module already loaded. Reboot recommended to ensure new KO takes effect."
else
    echo_string_nonewline "Loading module (insmod) ... "
    $INSMOD "$KO_TO_LOAD" >> $LOGFILE 2>&1
    RET=$?
    if [ $RET -ne 0 ] ; then
        echo_string ""
        echo_string "Warning: insmod failed. Check dmesg for Unknown symbol."
        echo_string "The driver will be loaded automatically after reboot (systemd)."
    else
        echo_string "Done."
    fi
fi

echo_string ""
echo_string "========================================================"
echo_string ""
echo_string "Install Successfully!"
echo_string "Auto-load at boot is enabled: hws.service"
echo_string "For more information please check the docs directory or"
echo_string "contact alex.liu@longtimetech.com."
echo_string ""
echo_string "========================================================"
echo_string ""
