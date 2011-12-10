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

binutilsv=binutils
linuxv=linux
gccv=gcc
libcv=eglibc

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
extra_eglibc_configure_opts=
arch=$1
default_libdir_name=lib
case $arch in
    arm)
        target=arm-linux-gnueabi
        linux_arch=arm
        ;;
    mipsel|mips|mips64)
	if [ "$arch" = "mips64" ]; then
	    default_libdir_name=lib32
	fi
        target=$arch-linux-gnu
        linux_arch=mips
	extra_binutils_configure_opts="$extra_binutils_configure_opts --disable-werror"
        ;;
    mpc)
        target=powerpc-linux-gnuspe
        linux_arch=powerpc
	extra_binutils_configure_opts="$extra_binutils_configure_opts --disable-werror"
        ;;
    ppc)
        target=powerpc-linux-gnu
        linux_arch=powerpc
	extra_binutils_configure_opts="$extra_binutils_configure_opts --disable-werror"
        ;;
    ppc64|powerpc64)
        target=powerpc64-linux-gnu
        linux_arch=powerpc
	default_libdir_name=lib64
	extra_binutils_configure_opts="$extra_binutils_configure_opts --enable-targets=powerpc-linux --disable-werror"
        ;;
    sh3|sh4|sh64)
        target=$arch-linux-gnu
        linux_arch=sh
	if [ "$arch" = "sh3" ]; then
	    extra_eglibc_configure_opts="--without-fp"
	fi
        ;;
    x86)
        target=i586-linux-gnu
        linux_arch=x86
        extra_gcc_configure_opts="$extra_gcc_configure_opts --with-arch=i586"
        ;;
    x86_64)
        target=x86_64-linux-gnu
        linux_arch=x86
	default_libdir_name=lib64
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
#  svn co -q svn://svn.eglibc.org/trunk eglibc
#  cd $libcv/libc
#  ln -s ../ports .
#  cd -
  cp -a ~/work/$libcv .
  cd $libcv/libc
  ln -s ../ports
# do not generate configure scripts. You dont know if your
# autoconf version is right or not.
  find . -name configure -exec touch '{}' ';'
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

#if [ $download_src = "yes" ]; then
#download
#else
#gccv=`ls $src/gcc-*.tar.bz2|xargs basename`
#gccv=${gccv:4:12}
#fi

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
make -j $parallelism all-binutils all-ld all-gas all-gold && touch .compiled
check_return "binutils compile"
fi
if [ ! -e .installed ]; then
make -j $parallelism install-ld install-gas install-binutils install-gold && touch .installed
check_return "binutils install"
fi

echo "Doing GCC phase 1 ..."
mkdir -p $obj/gcc1
cd $obj/gcc1
if [ ! -e .configured ]; then
$src/$gccv/configure \
     --target=$target \
     --prefix=$tools \
     --without-header \
     --with-newlib \
     --disable-shared --disable-threads --disable-libssp \
     --disable-libgomp --disable-libmudflap --disable-libquadmath \
     --enable-languages=c $extra_gcc_configure_opts \
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

# do not generate configure scripts. You dont know if your
# autoconf version is right or not.
cd $src/$libcv
find . -name configure -exec touch '{}' ';'
cd $src/$libcv/libc
ln -sf ../ports

case $arch in
mips64)
	# n64
	echo "Doing eglibc-n64 headers ..."
        mkdir -p $obj/eglibc-headers-n64
        cd $obj/eglibc-headers-n64
	if [ ! -e .configured ]; then
        BUILD_CC=gcc \
        CFLAGS='-g -O2 -fgnu89-inline' \
        CC="$tools/bin/$target-gcc -mabi=64" \
        CXX="$tools/bin/$target-g++ -mabi=64" \
        AR=$tools/bin/$target-ar \
        RANLIB=$tools/bin/$target-ranlib \
        LD=$tools/bin/$target-ld \
        AS=$tools/bin/$target-as \
        NM=$tools/bin/$target-nm \
        $src/$libcv/libc/configure \
            --prefix=/usr \
            --with-headers=$sysroot/usr/include \
            --build=$build \
            --host=$target \
            --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
        fi

	if [ ! -e .compiled ]; then
        make PARALLELMFLAGS=-j$parallelism install-headers \
                     install_root=$sysroot \
                     install-bootstrap-headers=yes \
		     && touch .compiled

	check_return "eglibc headers-n64 install"

	mkdir -p $sysroot/usr/lib64
	make csu/subdir_lib
	cp csu/crt[1in].o $sysroot/usr/lib64
	$tools/bin/$target-gcc -mabi=64 -nostdlib -nostartfiles -shared -x c /dev/null \
                       -o $sysroot/usr/lib64/libc.so
        fi
	# o32
	echo "Doing eglibc-o32 headers ..."
        mkdir -p $obj/eglibc-headers-o32
        cd $obj/eglibc-headers-o32
	if [ ! -e .configured ]; then
        BUILD_CC=gcc \
        CFLAGS='-g -O2 -fgnu89-inline' \
	CC="$tools/bin/$target-gcc -mabi=32" \
        CXX="$tools/bin/$target-g++ -mabi=32" \
        AR=$tools/bin/$target-ar \
        RANLIB=$tools/bin/$target-ranlib \
        LD=$tools/bin/$target-ld \
        AS=$tools/bin/$target-as \
        NM=$tools/bin/$target-nm \
        $src/$libcv/libc/configure \
            --prefix=/usr \
            --with-headers=$sysroot/usr/include \
            --build=$build \
            --host=$target \
            --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
	fi
	if [ ! -e .compiled ]; then
        make PARALLELMFLAGS=-j$parallelism install-headers \
                     install_root=$sysroot \
                     install-bootstrap-headers=yes \
		     && touch .compiled

	check_return "eglibc headers-o32 install"
	
	mkdir -p $sysroot/usr/lib
	make csu/subdir_lib
	cp csu/crt[1in].o $sysroot/usr/lib
	$tools/bin/$target-gcc -mabi=32 -nostdlib -nostartfiles -shared -x c /dev/null \
                       -o $sysroot/usr/lib/libc.so
        fi
	;;
ppc64)
        # 32-bit
	echo "Doing eglibc 32-bit headers ..."
        mkdir -p $obj/eglibc-headers-32
        cd $obj/eglibc-headers-32
	if [ ! -e .configured ]; then
        BUILD_CC=gcc \
        CFLAGS='-g -O2 -fgnu89-inline' \
        CC="$tools/bin/$target-gcc -m32" \
        CXX="$tools/bin/$target-g++ -m32" \
        AR=$tools/bin/$target-ar \
        RANLIB=$tools/bin/$target-ranlib \
        LD=$tools/bin/$target-ld \
        AS=$tools/bin/$target-as \
        NM=$tools/bin/$target-nm \
        $src/$libcv/libc/configure \
            --prefix=/usr \
            --with-headers=$sysroot/usr/include \
            --build=$build \
            --host=powerpc-linux-gnu \
            --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
	fi
	if [ ! -e .compiled ]; then
        make PARALLELMFLAGS=-j$parallelism install-headers \
                     install_root=$sysroot \
                     install-bootstrap-headers=yes \
		     && touch .compiled
	check_return "eglibc headers-32 install"

        mkdir -p $sysroot/usr/lib
        make csu/subdir_lib && touch .compiled
        cp csu/crt[1in].o $sysroot/usr/lib
        $tools/bin/$target-gcc -m32 -nostdlib -nostartfiles -shared \
	    -x c /dev/null -o $sysroot/usr/lib/libc.so
        fi
        ;;
x86_64)
        # 32-bit
	echo "Doing eglibc 32-bit headers ..."
        mkdir -p $obj/eglibc-headers-32
        cd $obj/eglibc-headers-32
	if [ ! -e .configured ]; then
        BUILD_CC=gcc \
        CFLAGS='-g -O2 -fgnu89-inline' \
        CC="$tools/bin/$target-gcc -m32 -march=i686" \
        CXX="$tools/bin/$target-g++ -m32 -march=i686" \
        AR=$tools/bin/$target-ar \
        RANLIB=$tools/bin/$target-ranlib \
        LD=$tools/bin/$target-ld \
        AS=$tools/bin/$target-as \
        NM=$tools/bin/$target-nm \
        $src/$libcv/libc/configure \
            --prefix=/usr \
            --with-headers=$sysroot/usr/include \
            --build=$build \
            --host=i686-linux-gnu \
            --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
	fi
	if [ ! -e .compiled ]; then
        make PARALLELMFLAGS=-j$parallelism install-headers \
                     install_root=$sysroot \
                     install-bootstrap-headers=yes && touch .compiled
	check_return "eglibc headers-32 install"

        mkdir -p $sysroot/usr/lib
        make csu/subdir_lib && touch .compiled
        cp csu/crt[1in].o $sysroot/usr/lib
        $tools/bin/$target-gcc -m32 -march=i686 -nostdlib -nostartfiles -shared -x c /dev/null \
                       -o $sysroot/usr/lib/libc.so
        fi
	;;

*)
	;;
esac

echo "Doing eglibc default headers ..."
mkdir -p $obj/eglibc-headers
cd $obj/eglibc-headers
if [ ! -e .configured ]; then
    BUILD_CC=gcc \
    CFLAGS='-g -O2 -fgnu89-inline' \
    CC=$tools/bin/$target-gcc \
    CXX=$tools/bin/$target-g++ \
    AR=$tools/bin/$target-ar \
    RANLIB=$tools/bin/$target-ranlib \
    LD=$tools/bin/$target-ld \
    AS=$tools/bin/$target-as \
    NM=$tools/bin/$target-nm \
    $src/$libcv/libc/configure \
    --prefix=/usr \
    --with-headers=$sysroot/usr/include \
    --build=$build \
    --host=$target \
    --disable-profile --without-gd --without-cvs --enable-add-ons \
    $extra_eglibc_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
    make PARALLELMFLAGS=-j$parallelism install-headers \
    install_root=$sysroot \
    install-bootstrap-headers=yes && touch .compiled
    check_return "eglibc headers install"
	    
    mkdir -p $sysroot/usr/$default_libdir_name
    make csu/subdir_lib
    cp csu/crt[1in].o $sysroot/usr/$default_libdir_name
    $tools/bin/$target-gcc -nostdlib -nostartfiles -shared -x c /dev/null \
    -o $sysroot/usr/$default_libdir_name/libc.so
fi

echo "Doing GCC phase 2 ..."
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

case $arch in
    mips64)
	# eglibc n64
	echo "Doing eglibc n64 ..."
	
	mkdir -p $obj/eglibc-n64
	cd $obj/eglibc-n64
	if [ ! -e .configured ]; then
	BUILD_CC=gcc \
	AUTOCONF=autoconf-2.13 \
	CFLAGS='-g -O2 -fgnu89-inline' \
	CC="$tools/bin/$target-gcc -mabi=64" \
	CXX="$tools/bin/$target-g++ -mabi=64" \
	AR=$tools/bin/$target-ar \
	RANLIB=$tools/bin/$target-ranlib \
	LD=$tools/bin/$target-ld \
	AS=$tools/bin/$target-as \
	NM=$tools/bin/$target-nm \
	$src/$libcv/libc/configure \
	    --prefix=/usr \
	    --with-headers=$sysroot/usr/include \
	    --build=$build \
	    --host=$target \
	    --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
        fi
	if [ ! -e .compiled ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism \
	    && touch .compiled
	check_return "eglibc n64 compile"
	fi
	if [ ! -e .installed ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism install \
			   install_root=$sysroot && touch .installed
	check_return "eglibc n64 install"
	fi
	# eglibc o32
	echo "Doing eglibc o32 ..."

	mkdir -p $obj/eglibc-o32
	cd $obj/eglibc-o32
	if [ ! -e .configured ]; then
	BUILD_CC=gcc \
	AUTOCONF=autoconf-2.13 \
	CFLAGS='-g -O2 -fgnu89-inline' \
	CC="$tools/bin/$target-gcc -mabi=32" \
	CXX="$tools/bin/$target-g++ -mabi=32" \
	AR=$tools/bin/$target-ar \
	RANLIB=$tools/bin/$target-ranlib \
	LD=$tools/bin/$target-ld \
	AS=$tools/bin/$target-as \
	NM=$tools/bin/$target-nm \
	$src/$libcv/libc/configure \
	    --prefix=/usr \
	    --with-headers=$sysroot/usr/include \
	    --build=$build \
	    --host=$target \
	    --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
        fi
	if [ ! -e .compiled ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism \
	    && touch .compiled
	check_return "eglibc o32 compile"
	fi
	if [ ! -e .installed ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism install \
			   install_root=$sysroot && touch .installed
	check_return "eglibc o32 install"
        fi
	;;
    ppc64)
	# eglibc 32-bit
	echo "Doing eglibc 32-bit ..."
	mkdir -p $obj/eglibc-32
	cd $obj/eglibc-32
	if [ ! -e .configured ]; then
	BUILD_CC=gcc \
	AUTOCONF=autoconf-2.13 \
	CFLAGS='-g -O2 -fgnu89-inline' \
	CC="$tools/bin/$target-gcc -m32" \
	CXX="$tools/bin/$target-g++ -m32" \
	AR=$tools/bin/$target-ar \
	RANLIB=$tools/bin/$target-ranlib \
	LD=$tools/bin/$target-ld \
	AS=$tools/bin/$target-as \
	NM=$tools/bin/$target-nm \
	$src/$libcv/libc/configure \
	    --prefix=/usr \
	    --with-headers=$sysroot/usr/include \
	    --build=$build \
	    --host=powerpc-linux-gnu \
	    --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
        fi
	if [ ! -e .compiled ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism \
	    && touch .compiled
	check_return "eglibc 32 compile"
	fi
	if [ ! -e .installed ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism install \
			   install_root=$sysroot && touch .installed
	check_return "eglibc 32 install"
        fi
	;;
    x86_64)
	# eglibc 32-bit
	echo "Doing eglibc 32-bit ..."
	mkdir -p $obj/eglibc-32
	cd $obj/eglibc-32
	if [ ! -e .configured ]; then
	BUILD_CC=gcc \
	AUTOCONF=autoconf-2.13 \
	CFLAGS='-g -O2 -fgnu89-inline' \
	CC="$tools/bin/$target-gcc -m32 -march=i686" \
	CXX="$tools/bin/$target-g++ -m32 -march=i686" \
	AR=$tools/bin/$target-ar \
	RANLIB=$tools/bin/$target-ranlib \
	LD=$tools/bin/$target-ld \
	AS=$tools/bin/$target-as \
	NM=$tools/bin/$target-nm \
	$src/$libcv/libc/configure \
	    --prefix=/usr \
	    --with-headers=$sysroot/usr/include \
	    --build=$build \
	    --host=i686-linux-gnu \
	    --disable-profile --without-gd --without-cvs --enable-add-ons \
	    $extra_eglibc_configure_opts \
	    && touch .configured
        fi
	if [ ! -e .compiled ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism \
	    && touch .compiled
	check_return "eglibc 32 compile"
        fi
	if [ ! -e .installed ]; then
	PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism install \
			   install_root=$sysroot && touch .installed
	check_return "eglibc 32 install"
        fi
	;;
    *);;
esac

echo "Doing default eglibc ..."

mkdir -p $obj/eglibc
cd $obj/eglibc
if [ ! -e .configured ]; then
BUILD_CC=gcc \
AUTOCONF=autoconf-2.13 \
CFLAGS='-g -O2 -fgnu89-inline' \
CC=$tools/bin/$target-gcc \
CXX=$tools/bin/$target-g++ \
AR=$tools/bin/$target-ar \
RANLIB=$tools/bin/$target-ranlib \
LD=$tools/bin/$target-ld \
AS=$tools/bin/$target-as \
NM=$tools/bin/$target-nm \
$src/$libcv/libc/configure \
    --prefix=/usr \
    --with-headers=$sysroot/usr/include \
    --build=$build \
    --host=$target \
    --disable-profile --without-gd --without-cvs --enable-add-ons \
    $extra_eglibc_configure_opts \
    && touch .configured
fi
if [ ! -e .compiled ]; then
PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism && touch .compiled
check_return "eglibc compile"
fi
if [ ! -e .installed ]; then
PATH=$tools/bin:$PATH make PARALLELMFLAGS=-j$parallelism install \
			   install_root=$sysroot && touch .installed
check_return "eglibc install"
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
check_return "gcc3 compile"
fi
if [ ! -e .installed ]; then
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
	cp -d $tools/$target/lib/libgcc_s.so* $sysroot/lib
	cp -d $tools/$target/lib/libstdc++.so* $sysroot/usr/lib
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

#delete the ports link we created in libc
rm $src/$libcv/libc/ports

# testing eglibc in cross env

# $ cd $obj/eglibc
# $ make cross-test-wrapper='/home/kraj/work/eglibc/libc/scripts/cross-test-ssh.sh root@192.168.1.91' -k tests
