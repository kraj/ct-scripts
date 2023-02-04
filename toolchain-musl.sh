# !/bin/sh
if [ $# -ne 1 ]; then
    echo -en "
    Usage: `basename $0` <arch>
    Example: `basename $0` ppc64
    Make sure that binutilsv, linuxv, gccv, libcv, point to src of respective
    components usually the top directories
    For gcc you also need prerequisite libraries installed e.g. libmpfr-dev
    libgmp-dev libmpc-dev, gcc 4.5 also need libelf-dev installed on build
    system. Alternatively you can also untar them in the gcc sources.

    top and srctop should also be customized to your environment
    by default
    top=/export/TARGET
    src=top/../src
"
    exit 1
fi

# change these versions depending upon
# what you want your toolchain based on

binutilsv=binutils-gdb
linuxv=linux
gccv=gcc
libcv=musl

download_src=no

host=`uname --machine`
build=${host}-linux-gnu
host=$build
cpus=`cat /proc/cpuinfo | grep '^processor' | wc -l`
proc_per_cpu=2
parallelism=$(($cpus * $proc_per_cpu))
#extra_gcc_configure_opts="--enable-gold --enable-lto"
#extra_binutils_configure_opts="--enable-ld=default --enable-gold=yes"
extra_binutils_configure_opts="--disable-werror"
extra_musl_configure_opts=
arch=$1
default_libdir_name=lib
case $arch in
    arm64|aarch64)
        target=aarch64-linux-musl
        linux_arch=arm64
        default_libdir_name=lib64
        ;;
    arm)
        target=arm-linux-musleabi
        linux_arch=arm
        ;;
    armhf)
        target=arm-linux-musleabihf
        linux_arch=arm
        extra_gcc_configure_opts="--with-float=hard --with-fpu=vfp"
        ;;
    mipsel|mips|mips64)
        if [ "$arch" = "mips64" ]; then
          default_libdir_name=lib32
	      fi
        target=$arch-linux-musl
        linux_arch=mips
        extra_binutils_configure_opts="$extra_binutils_configure_opts --disable-werror"
        ;;
    mpc)
        target=powerpc-linux-muslspe
        linux_arch=powerpc
        extra_binutils_configure_opts="$extra_binutils_configure_opts --disable-werror"
        ;;
    ppc)
        target=powerpc-linux-musl
        linux_arch=powerpc
        extra_binutils_configure_opts="$extra_binutils_configure_opts --disable-werror"
        ;;
    ppc64|powerpc64)
        target=powerpc64-linux-musl
        linux_arch=powerpc
        default_libdir_name=lib64
        extra_binutils_configure_opts="$extra_binutils_configure_opts --enable-targets=powerpc-linux --disable-werror"
        ;;
    sh3|sh4|sh64)
        target=$arch-linux-musl
        linux_arch=sh
      	if [ "$arch" = "sh3" ]; then
	        extra_musl_configure_opts="--without-fp"
      	fi
        ;;
    x86)
        target=i686-linux-musl
        linux_arch=x86
        extra_gcc_configure_opts="$extra_gcc_configure_opts --with-arch=i686"
        ;;
    amd64|x86_64)
        target=x86_64-linux-musl
        linux_arch=x86
        default_libdir_name=lib64
        extra_gcc_configure_opts="$extra_gcc_configure_opts --disable-bootstrap"
        ;;
    *)
        echo "Specify one {arm mpc ppc ppc64 mips mipsel mips64 sh3 sh4 sh64} architecture to build."
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
obj=$top/obj
tools=$top/tools
sysroot=$top/sysroot

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
# git clone git://git.sourceware.org/musl musl
#  cd $libcv
# do not generate configure scripts. You dont know if your
# autoconf version is right or not.
  cd $currdir
}

check_return () {
  if [ $? -ne 0 ]
  then
    echo "Something went wrong in $1. Please check"
    echo "exiting .... "
    exit
  fi
}

finish() {
  if [ $gcc_patched ]; then
    mv $src/$gccv/gcc/cppdefault.cc.orig $src/$gccv/gcc/cppdefault.cc
  fi
}

trap finish EXIT

prep_gcc () {
  if [ $gcc_patched ]; then
    mkdir -p gcc
    touch gcc/t-oe
    cp $src/$gccv/gcc/defaults.h gcc/defaults.h
    sed -i '$i'"#define SYSTEMLIBS_DIR \"/\\$default_libdir_name/\""  gcc/defaults.h
  fi
}

prep_src () {
  if [ $gcc_patched ]; then
    cp $src/$gccv/gcc/cppdefault.cc $src/$gccv/gcc/cppdefault.cc.orig
    sed -i -e 's/\<STANDARD_STARTFILE_PREFIX_2\>//g' $src/$gccv/gcc/cppdefault.cc
  fi
#  cd $src/$binutilsv
#  for d in . bfd binutils gas gold gprof ld libctf opcodes; do
#    cd $d
#    rm -rf autom4te.cache
#    autoconf
#    cd -
#  done
}

eval grep '\<STANDARD_STARTFILE_PREFIX_2\>' $src/$gccv/gcc/cppdefault.cc >& /dev/null
gcc_patched=$?

#if [ $download_src = "yes" ]; then
#download
#else
#gccv=`ls $src/gcc-*.tar.bz2|xargs basename`
#gccv=${gccv:4:12}
#fi

prep_src

echo "Doing Binutils ..."
mkdir -p $obj/binutils
cd $obj/binutils
if [ ! -e .configured ]; then
$src/$binutilsv/configure \
     	--target=$target \
     	--prefix=$tools \
     	--with-sysroot=$sysroot \
      --enable-deterministic-archives \
      --disable-gdb \
      --disable-gdbserver \
      --disable-libdecnumber \
      --disable-readline \
      --disable-sim \
	$extra_binutils_configure_opts \
	&& touch .configured
#     --enable-targets=all
fi
if [ ! -e .compiled ]; then
make -j $parallelism && touch .compiled
check_return "binutils compile"
fi
if [ ! -e .installed ]; then
make -j $parallelism install && touch .installed
check_return "binutils install"
fi

echo "Doing GCC stage 1 ..."
mkdir -p $obj/gcc1
cd $obj/gcc1
prep_gcc
if [ ! -e .configured ]; then
  $src/$gccv/configure \
    --target=$target \
    --prefix=$tools \
    --disable-libssp --disable-libcilkrts \
    --enable-languages=c --disable-shared \
    --disable-threads \
    --disable-libatomic \
    --disable-decimal-float \
    --disable-libffi \
    --disable-libgomp \
    --disable-libitm \
    --disable-libmpx \
    --disable-libquadmath \
    --disable-libsanitizer \
    --without-headers --with-newlib \
    $extra_gcc_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
  PATH=$tools/bin:$PATH make -j $parallelism all-gcc all-target-libgcc && touch .compiled
  check_return "gcc1 compile"
fi
if [ ! -e .installed ]; then
  PATH=$tools/bin:$PATH make -j  $parallelism install-gcc install-target-libgcc && touch .installed
  check_return "gcc1 install"
fi

echo "Doing linux kernel headers ..."
#cp -r $src/$linuxv $obj/linux
mkdir -p $obj/linux
cd $src/$linuxv

if [ ! -e $obj/linux/.installed ]; then
  PATH=$tools/bin:$PATH \
  make -j $parallelism headers_install \
      ARCH=$linux_arch \
      CROSS_COMPILE=$target- \
      INSTALL_HDR_PATH=$sysroot/usr \
      O=$obj/linux \
      && touch $obj/linux/.installed
  check_return "linux kernel headers install"
fi

echo "Doing default musl ..."

mkdir -p $obj/musl
cd $obj/musl
if [ ! -e .configured ]; then
  BUILD_CC=gcc \
  CC=$tools/bin/$target-gcc \
  CXX=$tools/bin/$target-g++ \
  AR=$tools/bin/$target-ar \
  RANLIB=$tools/bin/$target-ranlib \
  LD=$tools/bin/$target-ld \
  AS=$tools/bin/$target-as \
  NM=$tools/bin/$target-nm \
  OBJCOPY=$tools/bin/$target-objcopy \
  OBJDUMP=$tools/bin/$target-objdump \
  RANLIB=$tools/bin/$target-ranlib \
  READELF=$tools/bin/$target-readelf \
  STRIP=$tools/bin/$target-strip \
  $src/$libcv/configure \
    --prefix=/usr \
    --exec-prefix=/usr \
    --syslibdir=/lib \
    --host=$arch \
    $extra_musl_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
  PATH=$tools/bin:$PATH make -j$parallelism && touch .compiled
  check_return "musl compile"
fi
if [ ! -e .installed ]; then
  PATH=$tools/bin:$PATH make -j$parallelism install \
			   DESTDIR=$sysroot && touch .installed
  check_return "musl install"
fi

echo "Doing GCC final ..."
mkdir -p $obj/gcc2
cd $obj/gcc2
prep_gcc
if [ ! -e .configured ]; then
  $src/$gccv/configure \
    --target=$target \
    --prefix=$tools \
    --with-sysroot=$sysroot \
    --enable-__cxa_atexit \
    --enable-shared --enable-threads \
    --disable-libssp --disable-libgomp \
    --disable-libmudflap --disable-libsanitizer \
    --disable-gnu-indirect-function \
    --enable-languages=c,c++ \
    $extra_gcc_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
  PATH=$tools/bin:$PATH make -j $parallelism && touch .compiled
  check_return "gcc final compile"
fi
if [ ! -e .installed ]; then
  PATH=$tools/bin:$PATH make -j $parallelism install && touch .installed
  check_return "gcc final install"
  case $arch in
  ppc64)
	  cp -d $tools/$target/lib64/libgcc_s.so* $sysroot/lib64
	  cp -d $tools/$target/lib64/libstdc++.so* $sysroot/usr/lib64
	  cp -d $tools/$target/lib/libgcc_s.so* $sysroot/lib
	  cp -d $tools/$target/lib/libstdc++.so* $sysroot/usr/lib
	  ;;
  x86_64)
	  cp -d $tools/lib/libgcc_s.so* $sysroot/lib
	  cp -d $tools/lib/libstdc++.so* $sysroot/usr/lib
	  cp -d $tools/lib64/libgcc_s.so* $sysroot/lib64
	  cp -d $tools/lib64/libstdc++.so* $sysroot/usr/lib64
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
