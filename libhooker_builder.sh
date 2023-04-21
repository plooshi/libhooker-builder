#!/usr/bin/env bash

debug=0
rootless=0
theos_mflags="FINALPACKAGE=1"
arch="iphoneos-arm"
build="build/"
path=""

while (( "$#" )); do
  case "$1" in
    -d|--debug)
      debug=1
      shift
      ;;
    -r|--rootless)
      rootless=1
      shift
      ;;
    *) # preserve positional arguments
      shift
      ;;
  esac
done


if [ "$debug" = "1" ]; then
	theos_mflags="FINALPACKAGE=0"
fi

if [ "$rootless" = "1" ]; then
    theos_mflags+=" THEOS_PACKAGE_SCHEME=rootless"
    arch="iphoneos-arm64"
    build="build/var/jb"
    path="/var/jb"
fi

builddir=$(mktemp -d)
outdir=$(pwd)
os=$(uname)
git clone https://github.com/coolstar/libhooker $builddir/libhooker
git clone https://github.com/plooshi/libhooker-basebins $builddir/basebins
if [ "$os" != "Darwin" ]; then
    git clone https://github.com/jceel/libxpc $builddir/libxpc
fi
# build libhooker
pushd $builddir/libhooker
sed 's/libhooker_LINKAGE_TYPE = both//' Makefile > Makefile2
mv Makefile2 Makefile
sed 's/TOOL_NAME = libhookerTest//' Makefile > Makefile2
mv Makefile2 Makefile
sed 's/libhookerTest/# libhookerTest/' Makefile > Makefile2
mv Makefile2 Makefile
make package $theos_mflags -j4
mv packages/*.deb $builddir/libhooker.deb
popd

# build basebins
pushd $builddir/basebins

cd tweakinject
if [ "$os" != "Darwin" ]; then
    rm -rf xpc
    cp -r $builddir/libxpc/xpc .
fi
make package $theos_mflags -j4
mv packages/*.deb $builddir/tweakinject.deb
cd ..

update_makefile() {
    if [ "$os" != "Darwin" ]; then
        sed "s@xcrun -sdk iphoneos clang@$THEOS/toolchain/linux/iphone/bin/clang -fuse-ld=$THEOS/toolchain/linux/iphone/bin/ld -target arm64-apple-ios -isysroot $THEOS/sdks/iPhoneOS14.5.sdk -miphoneos-version-min=11.0@" Makefile > Makefile2
        mv Makefile2 Makefile
    fi
    sed 's/ldid2/ldid/' Makefile > Makefile2
    mv Makefile2 Makefile
    if [ "$debug" = "1" ]; then
		sed 's/strip/@# strip/' Makefile > Makefile2
        mv Makefile2 Makefile
	elif [ "$os" != "Darwin" ]; then
        sed "s@strip@$THEOS/toolchain/linux/iphone/bin/strip@" Makefile > Makefile2
        mv Makefile2 Makefile
    fi
}

cd inject_criticald3
update_makefile
cd ..

cd libsyringe
update_makefile
if [ "$os" != "Darwin" ]; then
    curl -LO https://raw.githubusercontent.com/apple-oss-distributions/xnu/rel/xnu-8792/EXTERNAL_HEADERS/ptrauth.h
    sed 's/<ptrauth.h>/"ptrauth.h"/' dylib-inject.c > dylib-inject.c.new
    mv dylib-inject.c.new dylib-inject.c
fi
cd ..

cd libhooker-starter
update_makefile
cd ..

cd pspawn_payload
if [ "$os" != "Darwin" ]; then
    sed 's/ cc/ clang/' Makefile > Makefile2
    mv Makefile2 Makefile
    curl -LO https://raw.githubusercontent.com/apple-oss-distributions/xnu/rel/xnu-8792/EXTERNAL_HEADERS/ptrauth.h
fi
update_makefile
cd ..

# build basebins
make ROOTLESS=$rootless -j4

mv bin/inject_criticald $builddir/inject_criticald
mv bin/libsyringe $builddir/libsyringe
mv bin/libhooker $builddir/rcd-libhooker
mv bin/pspawn_payload.dylib $builddir/pspawn_payload.dylib

popd

pushd $builddir
# everything is built, generate our deb
dpkg-deb -R libhooker.deb build
dpkg-deb -R tweakinject.deb tinject

mkdir -p $build/usr/bin
mkdir -p $build/usr/lib
mkdir -p $build/usr/lib/TweakInject
mkdir -p $build/usr/libexec/libhooker
mkdir -p $build/Library
mkdir -p $build/Library/MobileSubstrate
mkdir -p $build/Library/Frameworks/CydiaSubstrate.framework
mkdir -p $build/etc/rc.d
ln -s $path/usr/lib/TweakInject $build/Library/MobileSubstrate/DynamicLibraries
ln -s $path/usr/lib/TweakInject $build/Library/TweakInject
ln -s $path/usr/lib/libsubstrate.dylib $build/Library/Frameworks/CydiaSubstrate.framework/CydiaSubstrate
ln -s $path/usr/lib/libsubstitute.dylib $build/usr/lib/libsubstitute.0.dylib
mv tinject/$path/Library/MobileSubstrate/DynamicLibraries/TweakInject.dylib $build/usr/lib/TweakInject.dylib
rm -rf tinject
mv rcd-libhooker $build/etc/rc.d/libhooker
mv inject_criticald $build/usr/libexec/libhooker/inject_criticald
mv pspawn_payload.dylib $build/usr/libexec/libhooker/pspawn_payload.dylib
cp libsyringe $build/usr/libexec/libhooker/libsyringe
ln -s $path/usr/libexec/libhooker/libsyringe $build/usr/bin/cynject

# files are in place, setup DEBIAN things
cat <<EOF > build/DEBIAN/control
Package: org.coolstar.libhooker-oss
Architecture: $arch
Name: libhooker-oss
Description: libhooker, open source edition.
Author: Ploosh <me@ploosh.dev>, CoolStar <coolstarorganization@gmail.com>
Icon: https://repo.ploosh.dev/assets/libhooker-oss.png
SileoDepiction: https://repo.ploosh.dev/meta/libhooker-oss.json
Version: 1.0.0
Maintainer: Ploosh <me@ploosh.dev>
Section: System
Depends: firmware (>= 11.0), cy+cpu.arm64, org.coolstar.safemode
Provides: com.ex.libsubstitute (= 2.0), org.coolstar.tweakinject (= 1.5.0), mobilesubstrate (= 99.4), libhooker-strap (= 1.1), com.saurik.substrate.safemode (= 2.0), org.coolstar.libhooker (= 1.7.0)
Replaces: com.ex.libsubstitute, org.coolstar.tweakinject, mobilesubstrate, libhooker-strap, com.saurik.substrate.safemode, org.coolstar.libhooker
Conflicts: com.ex.libsubstitute, org.coolstar.tweakinject, mobilesubstrate, libhooker-strap, com.saurik.substrate.safemode, org.coolstar.libhooker
EOF
cat <<EOF > build/DEBIAN/prerm
#!/bin/sh

finish() {
	f="\${1}"

	# No control fd: bail out
	[ -z "\${f}" ] || [ -z "\${SILEO}" ] && return

	read -r fd ver <<-\EOF
 			\${SILEO}
			EOF

	# Sileo control fd version < 1: bail out
	[ "\${ver}" -ge 1 ] || return

	echo "finish:\${f}" >&"\${fd}"
}

finish restart
exit 0
EOF
cat <<EOF > build/DEBIAN/postinst
#!/bin/sh

finish() {
	f="\${1}"

	# No control fd: bail out
	[ -z "\${f}" ] || [ -z "\${SILEO}" ] && return

	read -r fd ver <<-EOF
			\${SILEO}
			EOF

	# Sileo control fd version < 1: bail out
	[ "\${ver}" -ge 1 ] || return

	echo "finish:\${f}" >&"\${fd}"
}

LEGACYPATH=$path/Library/MobileSubstrate/DynamicLibraries
if [ -e \${LEGACYPATH} ] ; then
	if [ ! -L \${LEGACYPATH} ]; then
		echo "\${LEGACYPATH} is broken. Fixing..."
		mv \${LEGACYPATH}/* /usr/lib/TweakInject/ || true
		rm -rf \${LEGACYPATH}
		ln -s $path/usr/lib/TweakInject \${LEGACYPATH}
	fi
fi

if [ -z "\${SILEO}" ]; then uicache -p $path/Applications/SafeMode.app; fi

touch $path/.mount_rw
$path/etc/rc.d/libhooker > /dev/null

# Known bad daemons in case the user doesn't reboot
killall -9 proximitycontrold 2> /dev/null || true
killall -9 TrustedPeersHelper 2> /dev/null || true

finish restart
exit 0
EOF
cat <<EOF > build/DEBIAN/triggers
interest $path/usr/lib/TweakInject
interest $path/Library/TweakInject
interest $path/Library/MobileSubstrate/DynamicLibraries
EOF


chmod +x build/DEBIAN/prerm
chmod +x build/DEBIAN/postinst

# DEBIAN is setup, build the deb
dpkg-deb -Zxz -b build org.coolstar.libhooker-oss_1.0.0_$arch.deb
mv org.coolstar.libhooker-oss_1.0.0_$arch.deb $outdir
popd
rm -rf $builddir
