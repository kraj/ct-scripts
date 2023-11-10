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

cpus=`cat /proc/cpuinfo |grep processor |wc -l`
proc_per_cpu=2
parallelism=$(($cpus * $proc_per_cpu))

arch=$1

gccv=gcc
binutilsv=binutils-gdb
newlibv=newlib
gdbv=binutils-gdb

case ${arch} in
    aarch64)
#	target=arm-elf
	target=aarch64-eabi
	extra_gcc_configure_opts="--disable-multilib"
  ;;
    arm)
#	target=arm-elf
	target=arm-eabi
#	extra_gcc_configure_opts="--disable-multilib --with-interwork \
#	--disable-werror --with-arch=armv7-a --with-tune=cortex-a8 \
#	--with-fpu=vfp --with-mode=thumb"
#	extra_gcc_configure_opts="--disable-multilib --with-interwork \
#	--disable-werror --with-arch=armv6j --with-tune=arm1136jf-s \
#	--with-float=softfp --with-fpu=vfp"
	extra_gcc_configure_opts="--disable-multilib"
	;;
    ppc64)
	target=powerpc64-elf
	extra_gcc_configure_opts=
	;;
    ppc)
      target=powerpc-elf
      extra_gcc_configure_opts=
        ;;
    mips64)
	target=mips64-elf
	extra_gcc_configure_opts="--enable-multilib --disable-werror"
	;;
    mips)
	target=mips-elf
	extra_gcc_configure_opts="--disable-werror"
	;;
    sparc)
	target=sparc64-elf
	extra_gcc_configure_opts=
	;;
    iwmmxt)
	target=arm-iwmmxt-elf
	extra_gcc_configure_opts=
	;;
    
    *)
	echo Architecture "${arch}" not supported
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

top=$top/$target
obj=$top/objdir
tools=$top/tools
sysroot=$top/sysroot

finish() {
  if [ $gcc_patched ]; then
    mv $src/$gccv/gcc/cppdefault.$ext.orig $src/$gccv/gcc/cppdefault.$ext
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
    cp $src/$gccv/gcc/cppdefault.$ext $src/$gccv/gcc/cppdefault.$ext.orig
    sed -i -e 's/\<STANDARD_STARTFILE_PREFIX_2\>//g' $src/$gccv/gcc/cppdefault.$ext
  fi
  cd $src/$binutilsv
  for d in . bfd binutils gas gold gprof ld libctf opcodes; do
    cd $d
    rm -rf autom4te.cache
    autoconf
    cd -
  done
}

if [ -e $src/$gccv/gcc/cppdefault.c ]; then
  ext=c
elif [ -e $src/$gccv/gcc/cppdefault.cc ]; then
  ext=cc
fi

eval grep '\<STANDARD_STARTFILE_PREFIX_2\>' $src/$gccv/gcc/cppdefault.$ext >& /dev/null
gcc_patched=$?

# uncomment if want to generate debuggable toolchain components.
#makeflags="CFLAGS='-O0 -g3'"
rm -rf $BASE
mkdir -p ${obj}/binutils-build
mkdir -p ${obj}/gcc-build
mkdir -p ${obj}/gdb-build
mkdir -p ${obj}/newlib-build

prep_src

echo "+-----------------------------------------------+"
echo "|               Doing Binutils                  |"
echo "+-----------------------------------------------+"
cd ${obj}/binutils-build
if [ ! -e .configured ]; then
	eval $makeflags \
	${src}/$binutilsv/configure \
	--target=${target} \
	--prefix=${tools} ${extra_binutils_configure_opts} \
  --enable-deterministic-archives \
  --disable-gdb \
  --disable-gdbserver \
  --disable-libdecnumber \
  --disable-readline \
  --disable-sim \
  --disable-werror \
	--enable-install-bfd && touch .configured
fi
if [ ! -e .compiled ]; then
	make -j$parallelism && touch .compiled
fi
if [ ! -e .installed ]; then
	make -j$parallelism install && touch .installed
fi

if [ "$?"  -ne 0 ];then
    echo "Error while building Binutils"
    exit 1
fi

export PATH="$PATH:${tools}/bin"

echo "+-----------------------------------------------+"
echo "|               Doing gcc & newlib              |"
echo "+-----------------------------------------------+"
ln -s ${src}/$newlibv/newlib ${src}/$gccv
ln -s ${src}/$newlibv/libgloss ${src}/$gccv
cd ${obj}/gcc-build

prep_gcc

if [ ! -e .configured ]; then
	eval $makeflags \
	${src}/$gccv/configure \
	--target=${target} \
	--prefix=${tools} ${extra_gcc_configure_opts} \
	--enable-languages="c,c++" \
	--with-newlib && touch .configured
#	--with-headers=${src}/$newlibv/newlib/libc/include

fi
if [ ! -e .compiled ]; then
	make -j$parallelism && touch .compiled
fi
if [ ! -e .installed ]; then
	make -j$parallelism install && touch .installed
fi

if [ "$?"  -ne 0 ];then
    echo "Error while building gcc & newlib"
    exit 1
fi

#echo "+-----------------------------------------------+"
#echo "|               Doing newlib                    |"
#echo "+-----------------------------------------------+"
#cd ${obj}/newlib-build
#if [ ! -e config.cache ]; then
#	eval $makeflags \
#        ${src}/$newlibv/configure \
#	--target=${target} \
#        --prefix=${tools} ${extra_gcc_configure_opts}
#
#fi
#make -j$parallelism all-target-newlib all-target-libgloss
#make -j$parallelism install-target-newlib install-target-libgloss
#if [ "$?"  -ne 0 ];then
#    echo "Error while building newlib"
#    exit 1
#fi

#echo "+-----------------------------------------------+"
#echo "|               Doing final gcc                 |"
#echo "+-----------------------------------------------+"
#cd ${obj}/gcc-build
#make -j$parallelism
#make install
#if [ "$?"  -ne 0 ];then
#    echo "Error while building final gcc"
#    exit 1
#fi

echo "+-----------------------------------------------+"
echo "|               Doing GDB                       |"
echo "+-----------------------------------------------+"
cd ${obj}/gdb-build
if [ ! -e .configured ]; then
	eval $makeflags \
	${src}/$gdbv/configure \
	--target=${target} \
	--prefix=${tools} \
	--disable-werror --disable-nls \
	${extra_gdb_configure_opts} \
	--enable-sim \
	--with-x=no --disable-gdbtk && touch .configured
fi
if [ ! -e .compiled ]; then
	make -j$parallelism all-gdb all-sim && touch .compiled
fi
if [ ! -e .installed ]; then
	make -j$parallelism install-gdb install-sim && touch .installed
fi

if [ "$?"  -ne 0 ];then
    echo "Error while building GDB"
    exit 1
fi
rm ${src}/$gccv/newlib
rm ${src}/$gccv/libgloss

echo "------------------- All Done! -------------------"
