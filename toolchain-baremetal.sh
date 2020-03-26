#!/usr/bin/env bash
# how to build mpfr and gmp
# ./prepare --with-gmp-build=<gmpbuilddir>
# make
# select which arch to build
#set -e

if [ $# -ne 1 ]; then
    echo -en "
    Usage: `basename $0` <arch>
    Example: `basename $0` ppc64
"
    exit 1
fi

CPUS=`cat /proc/cpuinfo |grep processor |wc -l`
CPUS=$(($CPUS * 2))
ARCH=$1

GCC_VER=gcc
BINUTILS_VER=binutils-gdb
NEWLIB_VER=newlib
GDB_VER=binutils-gdb

case ${ARCH} in
    arm)
#	TARGET=arm-elf
	TARGET=arm-eabi
#	CONFIG_FLAGS="--disable-multilib --with-interwork \
#	--disable-werror --with-arch=armv7-a --with-tune=cortex-a8 \
#	--with-fpu=vfp --with-mode=thumb"
#	CONFIG_FLAGS="--disable-multilib --with-interwork \
#	--disable-werror --with-arch=armv6j --with-tune=arm1136jf-s \
#	--with-float=softfp --with-fpu=vfp"
	CONFIG_FLAGS="--disable-multilib"
	;;
    ppc64)
	TARGET=powerpc64-elf
	CONFIG_FLAGS=
	;;
    ppc)
      TARGET=powerpc-elf
      CONFIG_FLAGS=
        ;;
    mips64)
	TARGET=mips64-elf
	CONFIG_FLAGS="--enable-multilib --disable-werror"
	;;
    mips)
	TARGET=mips-elf
	CONFIG_FLAGS="--disable-werror"
	;;
    sparc)
	TARGET=sparc64-elf
	CONFIG_FLAGS=
	;;
    iwmmxt)
	TARGET=arm-iwmmxt-elf
	CONFIG_FLAGS=
	;;
    
    *)
	echo Architecture "${ARCH}" not supported
	exit 1
	;;
esac
if [ "$top" == "" ]; then
    echo "top variable is empty. It should point to top of the build trees. Please add it to your environment"
    exit 1
fi
if [ "$src" == "" ]; then
    echo "src variable is empty. It should point to top dir where all source trees are. Please add it to your enviroment"
    exit 1
fi

BASE=$top/$TARGET
OBJBASE=$BASE/objdir
SRCBASE=$src
PREFIX=$BASE/tools

finish() {
  if [ $gcc_patched ]; then
    mv $src/$gccv/gcc/cppdefault.c.orig $src/$gccv/gcc/cppdefault.c
  fi
}

trap finish EXIT

prep_gcc () {
  if [ $gcc_patched ]; then
    mkdir gcc
    touch gcc/t-oe
    cp $src/$gccv/gcc/defaults.h gcc/defaults.h
    sed -i '$i'"#define SYSTEMLIBS_DIR \"/\\$default_libdir_name/\""  gcc/defaults.h
  fi
}

prep_src () {
  if [ $gcc_patched ]; then
    cp $src/$gccv/gcc/cppdefault.c $src/$gccv/gcc/cppdefault.c.orig
    sed -i -e 's/\<STANDARD_STARTFILE_PREFIX_2\>//g' $src/$gccv/gcc/cppdefault.c
  fi
}

eval grep '\<STANDARD_STARTFILE_PREFIX_2\>' $src/$gccv/gcc/cppdefault.c >& /dev/null
gcc_patched=$?

# uncomment if want to generate debuggable toolchain components.
#MAKE_FLAGS="CFLAGS='-O0 -g3'"
rm -rf $BASE
mkdir -p ${OBJBASE}/binutils-build
mkdir -p ${OBJBASE}/gcc-build
mkdir -p ${OBJBASE}/gdb-build
mkdir -p ${OBJBASE}/newlib-build

prep_src

echo "+-----------------------------------------------+"
echo "|               Doing Binutils                  |"
echo "+-----------------------------------------------+"
cd ${OBJBASE}/binutils-build
if [ ! -e .configured ]; then
	eval $MAKE_FLAGS \
	${SRCBASE}/$BINUTILS_VER/configure \
	--target=${TARGET} \
	--prefix=${PREFIX} ${CONFIG_FLAGS} \
	--enable-install-bfd && touch .configured
fi
if [ ! -e .compiled ]; then
	make -j$CPUS all-gas all-binutils all-ld && touch .compiled
fi
if [ ! -e .installed ]; then
	make -j$CPUS install-gas install-binutils install-ld && touch .installed
fi

if [ "$?"  -ne 0 ];then
    echo "Error while building Binutils"
    exit 1
fi

export PATH="$PATH:${PREFIX}/bin"

echo "+-----------------------------------------------+"
echo "|               Doing gcc & newlib              |"
echo "+-----------------------------------------------+"
ln -s ${SRCBASE}/$NEWLIB_VER/newlib ${SRCBASE}/$GCC_VER
ln -s ${SRCBASE}/$NEWLIB_VER/libgloss ${SRCBASE}/$GCC_VER
cd ${OBJBASE}/gcc-build

prep_gcc

if [ ! -e .configured ]; then
	eval $MAKE_FLAGS \
	${SRCBASE}/$GCC_VER/configure \
	--target=${TARGET} \
	--prefix=${PREFIX} ${CONFIG_FLAGS} \
	--enable-languages="c,c++" \
	--with-newlib && touch .configured
#	--with-headers=${SRCBASE}/$NEWLIB_VER/newlib/libc/include

fi
if [ ! -e .compiled ]; then
	make -j$CPUS && touch .compiled
fi
if [ ! -e .installed ]; then
	make -j$CPUS install && touch .installed
fi

if [ "$?"  -ne 0 ];then
    echo "Error while building gcc & newlib"
    exit 1
fi

#echo "+-----------------------------------------------+"
#echo "|               Doing newlib                    |"
#echo "+-----------------------------------------------+"
#cd ${OBJBASE}/newlib-build
#if [ ! -e config.cache ]; then
#	eval $MAKE_FLAGS \
#        ${SRCBASE}/$NEWLIB_VER/configure \
#	--target=${TARGET} \
#        --prefix=${PREFIX} ${CONFIG_FLAGS}
#
#fi
#make -j$CPUS all-target-newlib all-target-libgloss
#make -j$CPUS install-target-newlib install-target-libgloss
#if [ "$?"  -ne 0 ];then
#    echo "Error while building newlib"
#    exit 1
#fi

#echo "+-----------------------------------------------+"
#echo "|               Doing final gcc                 |"
#echo "+-----------------------------------------------+"
#cd ${OBJBASE}/gcc-build
#make -j$CPUS
#make install
#if [ "$?"  -ne 0 ];then
#    echo "Error while building final gcc"
#    exit 1
#fi

echo "+-----------------------------------------------+"
echo "|               Doing GDB                       |"
echo "+-----------------------------------------------+"
cd ${OBJBASE}/gdb-build
if [ ! -e .configured ]; then
	eval $MAKE_FLAGS \
	${SRCBASE}/$GDB_VER/configure \
	--target=${TARGET} \
	--prefix=${PREFIX} \
	--disable-werror --disable-nls \
	${CONFIG_FLAGS} \
	--enable-sim \
	--with-x=no --disable-gdbtk && touch .configured
fi
if [ ! -e .compiled ]; then
	make -j$CPUS all-gdb all-sim && touch .compiled
fi
if [ ! -e .installed ]; then
	make -j$CPUS install-gdb install-sim && touch .installed
fi

if [ "$?"  -ne 0 ];then
    echo "Error while building GDB"
    exit 1
fi
rm ${SRCBASE}/$GCC_VER/newlib
rm ${SRCBASE}/$GCC_VER/libgloss

echo "------------------- All Done! -------------------"
