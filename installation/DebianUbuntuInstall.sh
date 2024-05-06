#!/bin/bash
# This script downloads the source archive of SLiM, extracts it, creates a build
# directory and builds the command-line utilities for slim and eidos, and also
# the SLiMgui IDE. It then installs them to /usr/bin, and installs the
# FreeDesktop files to the appropriate places for desktop integration.

# Copyright © 2024 Bryce Carson

# Please report issues and submit pull requests against the SLiM-Extras GitHub
# repo, tagging Bryce.

# We need superuser privileges.
if [ "$(id -u)" -ne 0 ]; then
        echo 'This script must be run by root' >&2
	echo "Invoke the script with sudo."
        exit 1
fi

# Test that build requirements are satisfied. If any one requirement is unmet we
# say which.
unset cmakeinstalled qmakeinstalled qtchooserinstalled qtbase5devinstalled \
      curlinstalled wgetinstalled;

# Test if CMake is installed
dpkg-query -s cmake 2>/dev/null | grep -q ^"Status: install ok installed"$;
cmakeinstalled=$?

# Test if qmake is installed.
dpkg-query -s qt5-qmake 2>/dev/null | grep -q ^"Status: install ok installed"$;
qmakeinstalled=$?

# Test if qtchoosre is installed.
dpkg-query -s qtchooser 2>/dev/null | grep -q ^"Status: install ok installed"$;
qtchooserinstalled=$?

# Test if qtbase5-dev library is installed.
dpkg-query -s qtbase5-dev 2>/dev/null | grep -q ^"Status: install ok installed"$;
qtbase5devinstalled=$?

# Test if curl is installed.
dpkg-query -s curl 2>/dev/null | grep -q ^"Status: install ok installed"$;
curlinstalled=$?

# Test if wget is installed.
dpkg-query -s wget 2>/dev/null | grep -q ^"Status: install ok installed"$;
wgetinstalled=$?

[[ $qmakeinstalled == 0 && \
       $qtchooserinstalled == 0 && \
       $qtbase5devinstalled == 0 ]] || {
    echo "All of: qt5-qmake, qtchooser, and qtbase5-dev must be installed. \
Install the Qt5 requirements with 'sudo apt install qtbase5-dev qtchooser \
qt5-qmake'. Installing these packages ensures all build and runtime \
requirements are satisfied." | fold -sw 80;
}

[[ $cmakeinstalled == 0 ]] || {
    echo "cmake is not installed. Install it with 'sudo apt install cmake'.";
}

[[ $curlinstalled == 0 || $wgetinstalled == 0 ]] || {
    printf "Neither curl nor wget are installed. Install either with one \
of: 'sudo apt install wget', OR 'sudo apt install curl'." | fold -sw 80;
}

#Exit if qtchooser, qtbase5-dev, qt5-qmake, or cmake are not installed. If
#neither curl nor wget are installed, we exit later.
[[ $qtchooserinstalled == 0 && $qtbase5devinstalled == 0 && \
       $qmakeinstalled == 0 && $cmakeinstalled == 0 ]] || exit;

pushd `mktemp -d` || {
    printf "The Filesystem Hierarchy-standard directory /tmp does not exist, \
\$TMPDIR is not set, or some strange permissions issue exists with root and \
one of these locations. Resolve the issue by creating that directory; \
inspect this script, and your system, as other issues may exist." | fold -sw 80;
    exit;
}

if [[ $curlinstalled == 0 ]]; then
    { curl http://benhaller.com/slim/SLiM.zip > SLiM.zip && unzip SLiM.zip; } ||\
        {
            printf "Failed to download SLiM.zip or unzip it.\n";
            exit;
        }
elif [[ $wgetinstalled == 0 ]]; then
	  { wget http://benhaller.com/slim/SLiM.zip && unzip SLiM.zip; } || {
        printf "Failed to download SLiM.zip or unzip it.\n";
        exit;
    }
else { exit; } # Exit if neither curl nor wget is installed.
fi

# Proceed with building and installing if all tests succeeded.
{ mkdir BUILD && cd BUILD ;} || {
    echo "Root is unable to create /tmp/BUILD. It likely already exists. Try \
again after deleting it." | fold -sw 80;
    exit;
}
# The build process cmake will follow when building SLiMgui will install desktop
# integration files when the version of CMake is new enough, otherwise it will
# not.
{ cmake -D BUILD_SLIMGUI=ON ../SLiM && make -j"$(nproc)" ;} || {
    printf "Build failed. Please see the output and make a post on the \
slim-discuss mailing list. The output from this build is stored in \
'/var/log/' as SLiM-CMakeOutput-%s.log. You may be asked to upload this file \
during a support request." "$(date -Is)" | fold -sw 80
    mv /tmp/BUILD/CMakeFiles/CMakeOutput.log \
       /var/log/SLiM-CMakeOutput-"$(date -Is)".log;
    exit;
}

{ mkdir -p /usr/bin /usr/share/icons/hicolor/scalable/apps/ \
        /usr/share/icons/hicolor/scalable/mimetypes /usr/share/mime/packages \
        /usr/share/applications /usr/share/metainfo/; } || {
    echo "Some directory necessary for installation was not successfully \
created. Please see the output and make a post on the slim-discuss mailing \
list." | fold -sw 80;
    exit;
}

install slim eidos SLiMgui /usr/bin || {
    echo "Installation to /usr/bin was unsuccessful. Please see the output and \
make a post on the slim-discuss mailing list." | fold -sw 80;
    exit;
}


testversion=`mktemp`
cat <<EOF > ${testversion}
if(CMAKE_VERSION VERSION_LESS "3.14")
  message(FATAL_ERROR "CMAKE_VERSION is less than 3.14")
endif()
EOF
cmake -P ${testversion}
recentcmake=$?
if [[ $recentcmake -ne 0 ]]; then
    # Exit if installation unsuccessful.
    echo "Installation to /usr/bin was successful. Proceeding with desktop \
integration." | fold -sw 80;
    { mv ../SLiM/QtSLiM/icons/AppIcon64.svg \
         /usr/share/icons/hicolor/scalable/apps/org.messerlab.slimgui;
      mv ../SLiM/QtSLiM/icons/DocIcon.svg \
         /usr/share/icons/hicolor/scalable/mimetypes/text-slim.svg;
      mv ../SLiM/org.messerlab.slimgui-mime.xml /usr/share/mime/packages/;
      mv ../SLiM/org.messerlab.slimgui.desktop /usr/share/applications/;
      mv ../SLiM/org.messerlab.slimgui.appdata.xml /usr/share/metainfo/;

      update-mime-database -n /usr/share/mime/;
      xdg-mime install --mode system \
               /usr/share/mime/packages/org.messerlab.slimgui-mime.xml;
    } || {
        echo "Desktop integration failed. Please see the output and make a post
        on the slim-discuss mailing list." | fold -sw 80;
        exit;
    }

    echo "Desktop integration was successful. Temporary files will be removed."
fi

popd || {
    printf "For some reason could not change to ~ before deleting temporary \
directories." | fold -sw 80;
}

echo "Installation successful!"
DebianUbuntuInstallTempDir=`pwd` # The top of the directory stack.
rm -Rf ${DebianUbuntuInstallTempDir} || echo "Could not remove temporary files."
