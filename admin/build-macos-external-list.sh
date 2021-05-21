#!/usr/bin/env bash -xv
#
# Note: Requires coreutils to be installed so grealpath is available
#
# Build include file for cpack to build a complete macOS Bundle.
# List of executables whose shared libraries must also be included
#
# Exceptions:
# For now (6.2.0), need to do a few things manually first, like
#   1. Separate install command to avoid version number in GraphicsMagick directory name
#
# Notes:
#   1. This is tested on macports where gs is a symbolic link to gsc.

if [ $(which cmake) = "/opt/local/bin/cmake" ]; then
	distro=MacPorts
	top=/opt/local
elif [ $(which cmake) = "/opt/homebrew/bin/cmake" ]; then
	distro=HomeBrew
	top=/opt/homebrew
else
	echo "Requires MacPorts or HomeBrew, sorry"
	exit 1
fi

# Set temporary directory
TMPDIR=${TMPDIR:-/tmp}

if [ "Distro" = "MacPorts" ]; then
	# 1a. List of executables needed and whose shared libraries also are needed.
	#     Use full path if you need something not in your path
	EXEPLUSLIBS="${top}/bin/gsc ${top}/bin/gm ${top}/bin/ffmpeg ${top}/bin/ogr2ogr ${top}/bin/gdal_translate ${top}/lib/libfftw3f_threads.dylib"
	# 1b. List of any symbolic links needed
	#     Use full path if you need something not in your path
	EXELINKS=${top}/bin/gs
	# 1c. List of executables whose shared libraries have already been included via other shared libraries
	#     Use full path if you need something not in your path
	EXEONLY=
	# 1d. Shared directories to be added
	#     Use full path if you need something not in your path
	EXESHARED="gdal ${top}/share/ghostscript ${top}/lib/proj7/share/proj"
else
	EXEPLUSLIBS="${top}/bin/gsc ${top}/bin/gm ${top}/bin/ffmpeg ${top}/bin/ogr2ogr ${top}/bin/gdal_translate"
	EXELINKS=${top}/bin/gs ${top}/lib/libfftw3f_threads.dylib
	EXEONLY=
	EXESHARED="gdal ${top}/share/ghostscript ${top}/lib/share/proj"
fi
#-----------------------------------------
# 2a. Add the executables to the list given their paths
rm -f ${TMPDIR}/raw.lis
for P in ${EXEONLY} ${EXEPLUSLIBS}; do
	path=$(which $P)
	if [ -L $path ]; then # A symlink
		grealpath $path >> ${TMPDIR}/raw.lis
	else
		echo $path >> ${TMPDIR}/raw.lis
	fi
done
# 2b. Add the symbolic links to the list given their paths as is
for P in $EXELINKS; do
	which $P >> ${TMPDIR}/raw.lis
done
# 2c. Call otool -L recursively to list shared libraries used but exclude system libraries
cc admin/otoolr.c -o build/otoolr
build/otoolr $(pwd) ${EXEPLUSLIBS} >> ${TMPDIR}/raw.lis
# 4. sort into unique list then separate executables from libraries
sort -u ${TMPDIR}/raw.lis > ${TMPDIR}/final.lis
grep dylib ${TMPDIR}/final.lis > ${TMPDIR}/libraries.lis
grep -v dylib ${TMPDIR}/final.lis > ${TMPDIR}/programs.lis
# 5. Build the include file for cpack
cat << EOF
# List of extra executables and shared libraries to include in the macOS installer
# This file was prepared under $distro and used the installation paths of ${USER}.

install (PROGRAMS
EOF
awk '{printf "\t%s\n", $1}' ${TMPDIR}/programs.lis
cat << EOF
	DESTINATION \${GMT_BINDIR}
	COMPONENT Runtime)

install (PROGRAMS
EOF
awk '{printf "\t%s\n", $1}' ${TMPDIR}/libraries.lis
cat << EOF
	DESTINATION \${GMT_LIBDIR}
	COMPONENT Runtime)
EOF

# Optionally add shared resources
if [ ! "X$EXESHARED" = "X" ]; then
	echo ""
	echo "install (DIRECTORY"
fi
for P in $EXESHARED; do
	if [ $P = $(basename $P) ]; then
		echo "	$top/share/$P"
	else
		echo "	$P"
	fi
done
if [ ! "X$EXESHARED" = "X" ]; then
	echo "	DESTINATION share"
	echo "	COMPONENT Runtime)"
fi
cat << EOF

# Place the licenses for runtime dependencies
install (DIRECTORY
	../../admin/Licenses
	DESTINATION share
	COMPONENT Runtime)

# Place the GraphicsMagick config files
install (DIRECTORY
	${top}/lib/GraphicsMagick-\${GMT_CONFIG_GM_VERSION}/config
	DESTINATION \${GMT_LIBDIR}/GraphicsMagick
	COMPONENT Runtime)

install (FILES
	${top}/share/GraphicsMagick-\${GMT_CONFIG_GM_VERSION}/config/log.mgk
	DESTINATION \${GMT_LIBDIR}/GraphicsMagick/config
	COMPONENT Runtime)
EOF
