#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

make() {
    env make "-j${MAKE_PARALLEL:-$(nproc)}" "$@"
}

VERSION=$(grep '^CurrentVersion =' build-linux.rb | cut -d '"' -f2)

mkdir -p build
cd build

[ -e autowaf-1.7.14 ] || (
    mkdir autowaf-1.7.14
    cd autowaf-1.7.14
    git init
    git remote add origin https://github.com/drobilla/autowaf
    git fetch --depth=1 origin db72df3708286baa040c61dde62773b97ac40a2a
    git checkout db72df3708286baa040c61dde62773b97ac40a2a
    rm waf
)

[ -e waf-1.7.14 ] || (
    git clone --depth=1 https://gitlab.com/ita1024/waf.git -b waf-1.7.14 waf-1.7.14
    cd waf-1.7.14
    cp ../autowaf-1.7.14/autowaf.py waflib/extras/
    ./waf-light --make-waf --tools=autowaf
)

sha512sum waf-1.7.14/waf | cut -d ' ' -f1 > trusted-wafs

[ -e zynaddsubfx ] || (
    git clone --depth=1 https://github.com/zynaddsubfx/zynaddsubfx
    cd zynaddsubfx
    git submodule update --init --recursive
)

[ -e mruby-zest-build ] || (
    git clone --depth=1 https://github.com/mruby-zest/mruby-zest-build
    cd mruby-zest-build
    git am ../../patches/mruby-zest-build/*.patch
    git submodule update --init --recursive
    cp ../waf-1.7.14/waf deps/pugl/
)

find -name waf -print0 | while read -rd '' f; do
    if ! grep -xF "$(sha512sum "$f" | cut -d ' ' -f1)" trusted-wafs > /dev/null; then
        echo >&2 "untrusted waf: $f"
        exit 1
    fi
done

(
    cd mruby-zest-build
    ruby rebuild-fcache.rb
    make setup
    make builddep
)

(
    cd zynaddsubfx
    mkdir -p build
    cd build
    cmake .. -DGuiModule=zest -DDemoMode=false -DCMAKE_INSTALL_PREFIX=/usr/local \
        -DCMAKE_BUILD_TYPE=Release
    make
)

(
    cd mruby-zest-build
    make clean
    export VERSION
    export BUILD_MODE=release
    rm -f package/qml/*.qml
    ruby rebuild-fcache.rb
    make
    make pack
    rm package/qml/*.qml
)

OUT=zyn-fusion
rm -rf $OUT
mkdir $OUT
echo "Version $VERSION" > $OUT/VERSION
cp -r zynaddsubfx/instruments/ZynAddSubFX.lv2presets $OUT
cp -r zynaddsubfx/instruments/banks $OUT
cp mruby-zest-build/package/libzest.so $OUT
cp mruby-zest-build/package/zest $OUT/zyn-fusion
cp -r mruby-zest-build/package/font $OUT
mkdir $OUT/qml
touch $OUT/qml/MainWindow.qml
cp -r mruby-zest-build/package/schema $OUT
cp -r zynaddsubfx/build/src/Plugin/ZynAddSubFX/lv2 $OUT/ZynAddSubFX.lv2
cp zynaddsubfx/build/src/Plugin/ZynAddSubFX/vst/ZynAddSubFX.so $OUT
cp zynaddsubfx/build/src/zynaddsubfx $OUT
cp zynaddsubfx/COPYING $OUT/COPYING.zynaddsubfx

cat > $OUT/install-linux.sh << EOF
#!/bin/bash
set -euo pipefail
cd "\$(dirname "\$0")"
rm -rf /opt/zyn-fusion
cp -r . /opt/zyn-fusion
ln -sf /opt/zyn-fusion/zyn-fusion /usr/local/bin/
ln -sf /opt/zyn-fusion/zynaddsubfx /usr/local/bin/
mkdir -p /usr/local/share/zynaddsubfx
ln -sf /opt/zyn-fusion/banks /usr/local/share/zynaddsubfx/
mkdir -p /usr/local/lib/vst
ln -sf /opt/zyn-fusion/ZynAddSubFX.so /usr/local/lib/vst/
mkdir -p /usr/local/lib/lv2
ln -sf /opt/zyn-fusion/ZynAddSubFX.lv2 /usr/local/lib/lv2/
ln -sf /opt/zyn-fusion/ZynAddSubFX.lv2presets /usr/local/lib/lv2/
EOF
chmod +x $OUT/install-linux.sh

BUILD=$(dirname "$0")/build

cat >&2 << EOF
=====================================================================
built zyn-fusion in $BUILD/$OUT
run $BUILD/$OUT/install-linux.sh as root to install
=====================================================================
EOF
