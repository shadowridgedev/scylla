#!/bin/bash -e

. /etc/os-release
print_usage() {
    echo "build_deb.sh -target <codename> --dist --rebuild-dep --jobs 2"
    echo "  --target target distribution codename"
    echo "  --dist  create a public distribution package"
    echo "  --no-clean  don't rebuild pbuilder tgz"
    echo "  --jobs  specify number of jobs"
    exit 1
}
install_deps() {
    echo Y | sudo mk-build-deps
    DEB_FILE=`ls *-build-deps*.deb`
    sudo gdebi -n $DEB_FILE
    sudo rm -f $DEB_FILE
    sudo dpkg -P ${DEB_FILE%%_*.deb}
}

DIST=0
TARGET=
NO_CLEAN=0
JOBS=0
while [ $# -gt 0 ]; do
    case "$1" in
        "--dist")
            DIST=1
            shift 1
            ;;
        "--target")
            TARGET=$2
            shift 2
            ;;
        "--no-clean")
            NO_CLEAN=1
            shift 1
            ;;
        "--jobs")
            JOBS=$2
            shift 2
            ;;
        *)
            print_usage
            ;;
    esac
done

is_redhat_variant() {
    [ -f /etc/redhat-release ]
}
is_debian_variant() {
    [ -f /etc/debian_version ]
}


pkg_install() {
    if is_redhat_variant; then
        sudo yum install -y $1
    elif is_debian_variant; then
        sudo apt-get install -y $1
    else
        echo "Requires to install following command: $1"
        exit 1
    fi
}

if [ ! -e dist/debian/build_deb.sh ]; then
    echo "run build_deb.sh in top of scylla dir"
    exit 1
fi
if [ "$(arch)" != "x86_64" ]; then
    echo "Unsupported architecture: $(arch)"
    exit 1
fi

if [ -e debian ] || [ -e build/release ]; then
    sudo rm -rf debian build
    mkdir build
fi
if is_debian_variant; then
    sudo apt-get -y update
fi
# this hack is needed since some environment installs 'git-core' package, it's
# subset of the git command and doesn't works for our git-archive-all script.
if is_redhat_variant && [ ! -f /usr/libexec/git-core/git-submodule ]; then
    sudo yum install -y git
fi
if [ ! -f /usr/bin/git ]; then
    pkg_install git
fi
if [ ! -f /usr/bin/python ]; then
    pkg_install python
fi
if [ ! -f /usr/sbin/pbuilder ]; then
    pkg_install pbuilder
fi
if [ ! -f /usr/bin/dh_testdir ]; then
    pkg_install debhelper
fi

if [ -z "$TARGET" ]; then
    if is_debian_variant; then
        if [ ! -f /usr/bin/lsb_release ]; then
            pkg_install lsb-release
        fi
        TARGET=`lsb_release -c|awk '{print $2}'`
    else
        echo "Please specify target"
        exit 1
    fi
fi

VERSION=$(./SCYLLA-VERSION-GEN)
SCYLLA_VERSION=$(cat build/SCYLLA-VERSION-FILE | sed 's/\.rc/~rc/')
SCYLLA_RELEASE=$(cat build/SCYLLA-RELEASE-FILE)
echo $VERSION > version
./scripts/git-archive-all --extra version --force-submodules --prefix scylla-server ../scylla-server_$SCYLLA_VERSION-$SCYLLA_RELEASE.orig.tar.gz 

cp -a dist/debian/debian debian
cp dist/common/sysconfig/scylla-server debian/scylla-server.default
cp dist/debian/changelog.in debian/changelog
sed -i -e "s/@@VERSION@@/$SCYLLA_VERSION/g" debian/changelog
sed -i -e "s/@@RELEASE@@/$SCYLLA_RELEASE/g" debian/changelog
sed -i -e "s/@@CODENAME@@/$TARGET/g" debian/changelog
cp dist/debian/rules.in debian/rules
cp dist/debian/control.in debian/control
cp dist/debian/scylla-server.install.in debian/scylla-server.install
cp dist/debian/scylla-conf.preinst.in debian/scylla-conf.preinst
sed -i -e "s/@@VERSION@@/$SCYLLA_VERSION/g" debian/scylla-conf.preinst
if [ "$TARGET" = "jessie" ]; then
    sed -i -e "s/@@REVISION@@/1~$TARGET/g" debian/changelog
    sed -i -e "s/@@DH_INSTALLINIT@@//g" debian/rules
    sed -i -e "s/@@INSTALL_HK_DAILY_INIT@@/dh_installinit --no-start --name scylla-housekeeping-daily/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_RESTART_INIT@@/dh_installinit --no-start --name scylla-housekeeping-restart/g" debian/rules
    sed -i -e "s/@@INSTALL_FSTRIM@@/dh_installinit --no-start --name scylla-fstrim/g" debian/rules
    sed -i -e "s/@@INSTALL_NODE_EXPORTER@@/dh_installinit --no-start --name node-exporter/g" debian/rules
    sed -i -e "s#@@COMPILER@@#/opt/scylladb/bin/g++-7#g" debian/rules
    sed -i -e "s/@@BUILD_DEPENDS@@/libsystemd-dev, scylla-gcc73-g++-7, scylla-antlr35, scylla-libthrift010-dev, scylla-antlr35-c++-dev, scylla-libboost-program-options165-dev, scylla-libboost-filesystem165-dev, scylla-libboost-system165-dev, scylla-libboost-thread165-dev, scylla-libboost-test165-dev, libyaml-cpp-dev/g" debian/control
    sed -i -e "s/@@DEPENDS@@/realpath/g" debian/control
    sed -i -e "s#@@INSTALL@@##g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_D@@#dist/common/systemd/scylla-housekeeping-daily.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_R@@#dist/common/systemd/scylla-housekeeping-restart.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@FTDOTTIMER@@#dist/common/systemd/scylla-fstrim.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@SYSCTL@@#dist/debian/sysctl.d/99-scylla.conf etc/sysctl.d#g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_SAVE_COREDUMP@@#dist/debian/scripts/scylla_save_coredump usr/lib/scylla#g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_DELAY_FSTRIM@@#dist/debian/scripts/scylla_delay_fstrim usr/lib/scylla#g" debian/scylla-server.install
elif [ "$TARGET" = "stretch" ]; then
    sed -i -e "s/@@REVISION@@/1~$TARGET/g" debian/changelog
    sed -i -e "s/@@DH_INSTALLINIT@@//g" debian/rules
    sed -i -e "s/@@INSTALL_HK_DAILY_INIT@@/dh_installinit --no-start --name scylla-housekeeping-daily/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_RESTART_INIT@@/dh_installinit --no-start --name scylla-housekeeping-restart/g" debian/rules
    sed -i -e "s/@@INSTALL_FSTRIM@@/dh_installinit --no-start --name scylla-fstrim/g" debian/rules
    sed -i -e "s/@@INSTALL_NODE_EXPORTER@@/dh_installinit --no-start --name node-exporter/g" debian/rules
    sed -i -e "s#@@COMPILER@@#/opt/scylladb/bin/g++-7#g" debian/rules
    sed -i -e "s/@@BUILD_DEPENDS@@/libsystemd-dev, scylla-gcc73-g++-7, antlr3, scylla-libthrift010-dev, scylla-antlr35-c++-dev, scylla-libboost-program-options165-dev, scylla-libboost-filesystem165-dev, scylla-libboost-system165-dev, scylla-libboost-thread165-dev, scylla-libboost-test165-dev, scylla-libyaml-cpp05-dev/g" debian/control
    sed -i -e "s/@@DEPENDS@@/realpath/g" debian/control
    sed -i -e "s#@@INSTALL@@##g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_D@@#dist/common/systemd/scylla-housekeeping-daily.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_R@@#dist/common/systemd/scylla-housekeeping-restart.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@FTDOTTIMER@@#dist/common/systemd/scylla-fstrim.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@SYSCTL@@#dist/debian/sysctl.d/99-scylla.conf etc/sysctl.d#g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_SAVE_COREDUMP@@#dist/debian/scripts/scylla_save_coredump usr/lib/scylla#g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_DELAY_FSTRIM@@#dist/debian/scripts/scylla_delay_fstrim usr/lib/scylla#g" debian/scylla-server.install
elif [ "$TARGET" = "trusty" ]; then
    cp dist/debian/scylla-server.cron.d debian/
    sed -i -e "s/@@REVISION@@/0ubuntu1~$TARGET/g" debian/changelog
    sed -i -e "s/@@DH_INSTALLINIT@@/--upstart-only/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_DAILY_INIT@@/dh_installinit --no-start --name scylla-housekeeping --upstart-only/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_RESTART_INIT@@//g" debian/rules
    sed -i -e "s/@@INSTALL_FSTRIM@@//g" debian/rules
    sed -i -e "s/@@INSTALL_NODE_EXPORTER@@//g" debian/rules
    sed -i -e "s#@@COMPILER@@#/opt/scylladb/bin/g++-7#g" debian/rules
    sed -i -e "s/@@BUILD_DEPENDS@@/scylla-gcc73-g++-7, scylla-antlr35, scylla-libthrift010-dev, scylla-antlr35-c++-dev, scylla-libboost-program-options165-dev, scylla-libboost-filesystem165-dev, scylla-libboost-system165-dev, scylla-libboost-thread165-dev, scylla-libboost-test165-dev, libyaml-cpp-dev/g" debian/control
    sed -i -e "s/@@DEPENDS@@/realpath, hugepages, num-utils/g" debian/control
    sed -i -e "s#@@INSTALL@@#dist/debian/sudoers.d/scylla etc/sudoers.d#g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_D@@##g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_R@@##g" debian/scylla-server.install
    sed -i -e "s#@@FTDOTTIMER@@##g" debian/scylla-server.install
    sed -i -e "s#@@SYSCTL@@#dist/debian/sysctl.d/99-scylla.conf etc/sysctl.d#g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_SAVE_COREDUMP@@#dist/debian/scripts/scylla_save_coredump usr/lib/scylla#g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_DELAY_FSTRIM@@#dist/debian/scripts/scylla_delay_fstrim usr/lib/scylla#g" debian/scylla-server.install
elif [ "$TARGET" = "xenial" ]; then
    sed -i -e "s/@@REVISION@@/0ubuntu1~$TARGET/g" debian/changelog
    sed -i -e "s/@@DH_INSTALLINIT@@//g" debian/rules
    sed -i -e "s/@@INSTALL_HK_DAILY_INIT@@/dh_installinit --no-start --name scylla-housekeeping-daily/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_RESTART_INIT@@/dh_installinit --no-start --name scylla-housekeeping-restart/g" debian/rules
    sed -i -e "s/@@INSTALL_FSTRIM@@/dh_installinit --no-start --name scylla-fstrim/g" debian/rules
    sed -i -e "s/@@INSTALL_NODE_EXPORTER@@/dh_installinit --no-start --name node-exporter/g" debian/rules
    sed -i -e "s#@@COMPILER@@#/opt/scylladb/bin/g++-7#g" debian/rules
    sed -i -e "s/@@BUILD_DEPENDS@@/libsystemd-dev, scylla-gcc73-g++-7, antlr3, scylla-libthrift010-dev, scylla-antlr35-c++-dev, scylla-libboost-program-options165-dev, scylla-libboost-filesystem165-dev, scylla-libboost-system165-dev, scylla-libboost-thread165-dev, scylla-libboost-test165-dev, libyaml-cpp-dev/g" debian/control
    sed -i -e "s/@@DEPENDS@@/realpath, hugepages, /g" debian/control
    sed -i -e "s#@@INSTALL@@##g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_D@@#dist/common/systemd/scylla-housekeeping-daily.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_R@@#dist/common/systemd/scylla-housekeeping-restart.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@FTDOTTIMER@@#dist/common/systemd/scylla-fstrim.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@SYSCTL@@##g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_SAVE_COREDUMP@@##g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_DELAY_FSTRIM@@##g" debian/scylla-server.install
elif [ "$TARGET" = "bionic" ]; then
    sed -i -e "s/@@REVISION@@/0ubuntu1~$TARGET/g" debian/changelog
    sed -i -e "s/@@DH_INSTALLINIT@@//g" debian/rules
    sed -i -e "s/@@INSTALL_HK_DAILY_INIT@@/dh_installinit --no-start --name scylla-housekeeping-daily/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_RESTART_INIT@@/dh_installinit --no-start --name scylla-housekeeping-restart/g" debian/rules
    sed -i -e "s/@@INSTALL_FSTRIM@@/dh_installinit --no-start --name scylla-fstrim/g" debian/rules
    sed -i -e "s/@@INSTALL_NODE_EXPORTER@@/dh_installinit --no-start --name node-exporter/g" debian/rules
    sed -i -e "s#@@COMPILER@@#g++-7#g" debian/rules
    sed -i -e "s/@@BUILD_DEPENDS@@/libsystemd-dev, scylla-gcc73-g++-7, antlr3, scylla-libthrift010-dev, scylla-antlr35-c++-dev, scylla-libboost-program-options165-dev, scylla-libboost-filesystem165-dev, scylla-libboost-system165-dev, scylla-libboost-thread165-dev, scylla-libboost-test165-dev, libyaml-cpp-dev/g" debian/control
    sed -i -e "s/@@DEPENDS@@/coreutils, hugepages, /g" debian/control
    sed -i -e "s#@@INSTALL@@##g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_D@@#dist/common/systemd/scylla-housekeeping-daily.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_R@@#dist/common/systemd/scylla-housekeeping-restart.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@FTDOTTIMER@@#dist/common/systemd/scylla-fstrim.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@SYSCTL@@##g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_SAVE_COREDUMP@@##g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_DELAY_FSTRIM@@##g" debian/scylla-server.install
elif [ "$TARGET" = "yakkety" ] || [ "$TARGET" = "zesty" ] || [ "$TARGET" = "artful" ]; then
    sed -i -e "s/@@REVISION@@/0ubuntu1~$TARGET/g" debian/changelog
    sed -i -e "s/@@DH_INSTALLINIT@@//g" debian/rules
    sed -i -e "s/@@INSTALL_HK_DAILY_INIT@@/dh_installinit --no-start --name scylla-housekeeping-daily/g" debian/rules
    sed -i -e "s/@@INSTALL_HK_RESTART_INIT@@/dh_installinit --no-start --name scylla-housekeeping-restart/g" debian/rules
    sed -i -e "s/@@INSTALL_FSTRIM@@/dh_installinit --no-start --name scylla-fstrim/g" debian/rules
    sed -i -e "s/@@INSTALL_NODE_EXPORTER@@/dh_installinit --no-start --name node-exporter/g" debian/rules
    sed -i -e "s/@@COMPILER@@/g++-7/g" debian/rules
    sed -i -e "s/@@BUILD_DEPENDS@@/libsystemd-dev, g++-7, antlr3, scylla-libthrift010-dev, scylla-antlr35-c++-dev, libboost-program-options-dev, libboost-filesystem-dev, libboost-system-dev, libboost-thread-dev, libboost-test-dev, libyaml-cpp-dev/g" debian/control
    sed -i -e "s/@@DEPENDS@@/realpath, hugepages, /g" debian/control
    sed -i -e "s#@@INSTALL@@##g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_D@@#dist/common/systemd/scylla-housekeeping-daily.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@HKDOTTIMER_R@@#dist/common/systemd/scylla-housekeeping-restart.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@FTDOTTIMER@@#dist/common/systemd/scylla-fstrim.timer /lib/systemd/system#g" debian/scylla-server.install
    sed -i -e "s#@@SYSCTL@@##g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_SAVE_COREDUMP@@##g" debian/scylla-server.install
    sed -i -e "s#@@SCRIPTS_DELAY_FSTRIM@@##g" debian/scylla-server.install
else
    echo "Unknown distribution: $TARGET"
fi
if [ $DIST -gt 0 ]; then
    sed -i -e "s#@@ADDHKCFG@@#conf/housekeeping.cfg etc/scylla.d/#g" debian/scylla-server.install
else
    sed -i -e "s#@@ADDHKCFG@@##g" debian/scylla-server.install
fi
if [ "$TARGET" != "trusty" ]; then
    cp dist/common/systemd/scylla-server.service.in debian/scylla-server.service
    sed -i -e "s#@@SYSCONFDIR@@#/etc/default#g" debian/scylla-server.service
    if [ "$TARGET" = "jessie" ]; then
        sed -i -e "s#AmbientCapabilities=CAP_SYS_NICE##g" debian/scylla-server.service
    fi
    cp dist/common/systemd/scylla-housekeeping-daily.service.in debian/scylla-server.scylla-housekeeping-daily.service
    sed -i -e "s#@@REPOFILES@@#'/etc/apt/sources.list.d/scylla*.list'#g" debian/scylla-server.scylla-housekeeping-daily.service
    cp dist/common/systemd/scylla-housekeeping-restart.service.in debian/scylla-server.scylla-housekeeping-restart.service
    sed -i -e "s#@@REPOFILES@@#'/etc/apt/sources.list.d/scylla*.list'#g" debian/scylla-server.scylla-housekeeping-restart.service
    cp dist/common/systemd/scylla-fstrim.service debian/scylla-server.scylla-fstrim.service
    cp dist/common/systemd/node-exporter.service debian/scylla-server.node-exporter.service
fi

if [ $NO_CLEAN -eq 0 ]; then
    sudo rm -fv /var/cache/pbuilder/scylla-server-$TARGET.tgz
    sudo DIST=$TARGET /usr/sbin/pbuilder clean --configfile ./dist/debian/pbuilderrc
    sudo DIST=$TARGET /usr/sbin/pbuilder create --configfile ./dist/debian/pbuilderrc --allow-untrusted
fi
if [ $JOBS -ne 0 ]; then
    DEB_BUILD_OPTIONS="parallel=$JOBS"
fi
sudo DIST=$TARGET /usr/sbin/pbuilder update --configfile ./dist/debian/pbuilderrc --allow-untrusted
if [ "$TARGET" = "trusty" ] || [ "$TARGET" = "xenial" ] || [ "$TARGET" = "yakkety" ] || [ "$TARGET" = "zesty" ] || [ "$TARGET" = "artful" ] || [ "$TARGET" = "bionic" ]; then
    sudo DIST=$TARGET /usr/sbin/pbuilder execute --configfile ./dist/debian/pbuilderrc --save-after-exec dist/debian/ubuntu_enable_ppa.sh
elif [ "$TARGET" = "jessie" ] || [ "$TARGET" = "stretch" ]; then
    sudo DIST=$TARGET /usr/sbin/pbuilder execute --configfile ./dist/debian/pbuilderrc --save-after-exec dist/debian/debian_install_gpgkey.sh
fi
sudo -E DIST=$TARGET DEB_BUILD_OPTIONS=$DEB_BUILD_OPTIONS pdebuild --configfile ./dist/debian/pbuilderrc --buildresult build/debs
