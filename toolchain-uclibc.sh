# !/usr/bin/env bash

src=$HOME/work
defconfig_dir=$HOME/work/ct-scripts/uClibc-defconfigs

if [ $# -lt 1 ]; then
    echo -en "
Usage: `basename $0` <arch> {<config name>}
Example: `basename $0` ppc64 config.lt.mine
config.lt.mine is searched in $defconfig_dir
if no config name is specified then it will
contruct a config name config.<thread model>.<arch>
e.g. config.nptl.arm will be used if building
for arm using nptl and config.lt.arm will be
used if building for arm using linuxthreads
available configs are:

"
    ls $defconfig_dir
    exit 0
fi

# change these versions depending upon
# what you want your toolchain based on

#binutilsv=2.18.50
#linuxv=2.6.24
#gccv=4.2
#libcv=eglibc

#threadv=lt
binutilsv=binutils
linuxv=linux-2.6
gccv=gcc
libcv=uClibc
download_src=no

host=`uname --machine`
build=${host}-linux-gnu
host=$build
cpus=`cat /proc/cpuinfo | grep '^processor' | wc -l`
proc_per_cpu=2
parallelism=$(($cpus * $proc_per_cpu))
extra_gcc_configure_opts=
extra_binutils_configure_opts=
extra_eglibc_configure_opts=
arch=$1
defconfig=$2
threadv=nptl

case $arch in
    ppc)
        target=powerpc-linux-uclibc
        linux_arch=powerpc
	extra_binutils_configure_opts="--disable-werror"
	extra_gcc_configure_opts="--disable-multilib"
        ;;
    ppc64)
        target=powerpc64-linux-uclibc
        linux_arch=powerpc
	extra_binutils_configure_opts="--enable-targets=powerpc-linux-uclibc --disable-werror"
        ;;
    arm)
        target=arm-linux-uclibcgnueabi
        linux_arch=arm
	extra_binutils_configure_opts="--disable-werror"
        ;;
    x86)
        target=i586-linux-uclibc
        linux_arch=x86
        extra_gcc_configure_opts="$extra_gcc_configure_opts --with-arch=i586 --disable-libquadmath"
        ;;
    x86_64)
        target=x86_64-linux-uclibc
        linux_arch=x86
        extra_gcc_configure_opts="$extra_gcc_configure_opts --disable-libquadmath --disable-multilib"
        ;;
    mips|mipsel|mips64)
        target=$arch-linux-uclibc
        linux_arch=mips
	extra_binutils_configure_opts="--disable-werror"
        ;;
    mpc)
        target=powerpc-linux-uclibcspe
        linux_arch=powerpc
	extra_binutils_configure_opts="--disable-werror"
        ;;
    sh3|sh4|sh64)
	target=$arch-linux-uclibc
	linux_arch=sh
	;;
    *)
        echo "Specify one of {arm x86 x86_64 ppc mpc mips mips64 sh3 sh4 sh64} architecture to build."
        exit 1
        ;;
esac

top=$HOME/work/cross/$target
obj=$top/obj
tools=$top/tools
sysroot=$top/sysroot


if [ "$defconfig" == "" ]; then
    defconfig=$defconfig_dir/config.$threadv.$arch
fi
check_return () {
  if [ $? -ne 0 ]
  then
    echo "Something went wrong in $1. Please check"
    echo "exiting .... "
    exit
  fi
}

download () {
  mkdir -p $src
  local currdir=$PWD
  cd $src
  rm -rf *
  wget -q http://www.kernel.org/pub/linux/kernel/v2.6/linux-$linuxv.tar.bz2
  tar -xjf linux-$linuxv.tar.bz2
  wget -q ftp://mirrors.kernel.org/sources.redhat.com/gcc/snapshots/LATEST-$gccv/gcc-[0-9]*.tar.bz2
  gccv=`ls gcc-*.tar.bz2`
  gccv=${gccv:4:12}
tar -xjf gcc-$gccv.tar.bz2
wget -q ftp://mirrors.kernel.org/sources.redhat.com/binutils/snapshots/binutils-$binutilsv.tar.bz2
  tar -xjf binutils-$binutilsv.tar.bz2
#  svn co -q svn://svn.eglibc.org/trunk eglibc
#  cd $libcv/libc
#  ln -s ../ports .
#  popd
  cp -a ~/work/$libcv .
  cd $libcv/libc
  ln -s ../ports
# do not generate configure scripts. You dont know if your
# autoconf version is right or not.
  find . -name configure -exec touch '{}' ';'
  cd $currdir
}

#if [ $download_src = "yes" ]; then
#download
#else
#gccv=`ls $src/gcc-*.tar.bz2|xargs basename`
#gccv=${gccv:4:12}
#fi

#rm -rf $top/*
echo "Doing Binutils ..."
mkdir -p $obj/binutils
cd $obj/binutils
if [ ! -e .configured ]; then
$src/$binutilsv/configure \
     	--target=$target \
     	--prefix=$tools \
     	--with-sysroot=$sysroot \
	$extra_binutils_configure_opts \
	&& touch .configured
#     --enable-targets=all
fi
if [ ! -e .compiled ]; then
make -j $parallelism all-binutils all-ld all-gas && touch .compiled
check_return "binutils compile"
fi
if [ ! -e .installed ]; then
make -j $parallelism install-ld install-gas install-binutils && touch .installed
check_return "binutils install"
fi

echo "Doing GCC phase 1 ..."
mkdir -p $obj/gcc1
cd $obj/gcc1
if [ ! -e .configured ]; then
$src/$gccv/configure \
     --target=$target \
     --prefix=$tools \
     --without-headers --with-newlib \
     --disable-shared --disable-threads --disable-libssp \
     --disable-libgomp --disable-libmudflap --disable-libquadmath \
     --enable-languages=c $extra_gcc_configure_opts \
     && touch .configured
fi
if [ ! -e .compiled ]; then
PATH=$tools/bin:$PATH make -j $parallelism all-gcc && touch .compiled
check_return "gcc1 compile"
fi
if [ ! -e .installed ]; then
PATH=$tools/bin:$PATH make -j $parallelism install-gcc && touch .installed
check_return "gcc1 install"
fi
echo "Doing kernel headers ..."
#cp -r $src/$linuxv $obj/linux
mkdir -p $obj/linux
cd $src/$linuxv

if [ ! -e $obj/linux/.installed ]; then
PATH=$tools/bin:$PATH \
make -j $parallelism headers_install \
      ARCH=$linux_arch CROSS_COMPILE=$target- \
      INSTALL_HDR_PATH=$sysroot/usr \
      O=$obj/linux \
      && touch $obj/linux/.installed
check_return "linux kernel headers install"
fi

echo "Doing uclibc headers ..."

mkdir -p $obj/uclibc-headers
cd $src/$libcv
if [ ! -e $obj/uclibc-headers/.configured ]; then
PATH=$tools/bin:$PATH make CROSS=$target- PREFIX=$sysroot \
    O=$obj/uclibc-headers allnoconfig \
    KCONFIG_ALLCONFIG=$defconfig \
    && touch $obj/uclibc-headers/.configured
check_return "uclibc oldconfig"
# replace the sysroot/usr/include into KERNEL_HEADERS in .config
kern_headers=$sysroot/usr/include
sed -e "s,^KERNEL_HEADERS=.*,KERNEL_HEADERS=\"$kern_headers\"," < $obj/uclibc-headers/.config >$obj/uclibc-headers/.config.tmp
mv $obj/uclibc-headers/.config.tmp $obj/uclibc-headers/.config
fi
if [ ! -e $obj/uclibc-headers/.installed ]; then
PATH=$tools/bin:$PATH make CROSS=$target- PREFIX=$sysroot \
    O=$obj/uclibc-headers install_headers install_startfiles \
    && touch $obj/uclibc-headers/.installed
check_return "uclibc install_headers"
mkdir -p $sysroot/usr/lib
$tools/bin/$target-gcc -nostdlib -nostartfiles -shared -x c /dev/null \
                      -o $sysroot/usr/lib/libc.so
fi

echo "Doing GCC phase 2 ..."
#    --disable-decimal-float
mkdir -p $obj/gcc2
cd $obj/gcc2
if [ ! -e .configured ]; then
$src/$gccv/configure \
    --target=$target \
    --prefix=$tools \
    --with-sysroot=$sysroot \
    --disable-libssp --disable-libgomp \
    --disable-libmudflap --disable-libquadmath \
    --enable-languages=c $extra_gcc_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
PATH=$tools/bin:$PATH make -j $parallelism && touch .compiled
check_return "gcc2 compile"
fi
if [ ! -e .installed ]; then
PATH=$tools/bin:$PATH make -j $parallelism install && touch .installed
check_return "gcc2 install"
fi

echo "Doing uclibc ..."

mkdir -p $obj/uclibc
cd $src/$libcv
#(cd $obj; ln -sf $src/$libcv uclibc)
#cp -a $src/$libcv/* $obj/uclibc/
#cd $obj/uclibc
if [ ! -e $obj/uclibc/.configured ]; then
PATH=$tools/bin:$PATH make CROSS=$target- PREFIX=$sysroot \
    O=$obj/uclibc allnoconfig \
    KCONFIG_ALLCONFIG=$defconfig \
    && touch $obj/uclibc/.configured
# replace the sysroot/usr/include into KERNEL_HEADERS in .config
kern_headers=$sysroot/usr/include
sed -e "s,^KERNEL_HEADERS=.*,KERNEL_HEADERS=\"$kern_headers\"," < $obj/uclibc/.config >$obj/uclibc/.config.tmp
mv $obj/uclibc/.config.tmp $obj/uclibc/.config
fi
if [ ! -e $obj/uclibc/.compiled ]; then
PATH=$tools/bin:$PATH make CROSS=$target- PREFIX=$sysroot \
    STRIPTOOL=true O=$obj/uclibc all \
    && touch $obj/uclibc/.compiled
check_return "uclibc compile"
fi
if [ ! -e $obj/uclibc/.installed ]; then
PATH=$tools/bin:$PATH make CROSS=$target- PREFIX=$sysroot \
    STRIPTOOL=true O=$obj/uclibc install \
    && touch $obj/uclibc/.installed
check_return "uclibc install"
fi


echo "Doing GCC phase 3 ..."
mkdir -p $obj/gcc3
cd $obj/gcc3
if [ ! -e .configured ]; then
$src/$gccv/configure \
    --target=$target \
    --prefix=$tools \
    --with-sysroot=$sysroot \
    --enable-__cxa_atexit \
    --disable-libssp --disable-libgomp --disable-libmudflap \
    --enable-languages=c,c++ $extra_gcc_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
PATH=$tools/bin:$PATH make -j $parallelism && touch .compiled
fi
if [ ! -e .installed ]; then
check_return "gcc3 compile"
PATH=$tools/bin:$PATH make -j $parallelism install && touch .installed
check_return "gcc3 install"

case $arch in
ppc64)
	cp -d $tools/$target/lib64/libgcc_s.so* $sysroot/lib64
	cp -d $tools/$target/lib64/libstdc++.so* $sysroot/usr/lib64
	cp -d $tools/$target/lib/libgcc_s.so* $sysroot/lib
	cp -d $tools/$target/lib/libstdc++.so* $sysroot/usr/lib
	;;
x86_64)
#	cp -d $tools/$target/lib/libgcc_s.so* $sysroot/lib
#	cp -d $tools/$target/lib/libstdc++.so* $sysroot/usr/lib
	cp -d $tools/$target/lib64/libgcc_s.so* $sysroot/lib64
	cp -d $tools/$target/lib64/libstdc++.so* $sysroot/usr/lib64
	;;
mips64)
	cp -d $tools/$target/lib64/libgcc_s.so* $sysroot/lib64
	cp -d $tools/$target/lib64/libgcc_s.so* $sysroot/lib64
	cp -d $tools/$target/lib32/libstdc++.so* $sysroot/usr/lib32
	cp -d $tools/$target/lib32/libstdc++.so* $sysroot/usr/lib32
	cp -d $tools/$target/lib/libgcc_s.so* $sysroot/lib
	cp -d $tools/$target/lib/libstdc++.so* $sysroot/usr/lib
	;;
*)
	cp -d $tools/$target/lib/libgcc_s.so* $sysroot/lib
	cp -d $tools/$target/lib/libstdc++.so* $sysroot/usr/lib
	;;
esac
fi
echo "!!! All Done !!!"
