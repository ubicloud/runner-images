#!/bin/bash -e
################################################################################
##  File:  configure-dpkg.sh
##  Desc:  Configure dpkg
################################################################################

# Source the helpers for use with the script
source $HELPER_SCRIPTS/etc-environment.sh
source $HELPER_SCRIPTS/os.sh
# This is the anti-frontend. It never interacts with you  at  all,
# and  makes  the  default  answers  be used for all questions. It
# might mail error messages to root, but that's it;  otherwise  it
# is  completely  silent  and  unobtrusive, a perfect frontend for
# automatic installs. If you are using this front-end, and require
# non-default  answers  to questions, you will need to pre-seed the
# debconf database
set_etc_environment_variable "DEBIAN_FRONTEND" "noninteractive"

# dpkg can be instructed not to ask for confirmation
# when replacing a configuration file (with the --force-confdef --force-confold options)
cat <<EOF >> /etc/apt/apt.conf.d/10dpkg-options
Dpkg::Options {
  "--force-confdef";
  "--force-confold";
}
EOF

# hide information about packages that are no longer required
cat <<EOF >> /etc/apt/apt.conf.d/10apt-autoremove
APT::Get::AutomaticRemove "0";
APT::Get::HideAutoRemove "1";
EOF

# Install libicu70 package for Ubuntu 24
if  is_ubuntu24 ; then
  if is_arm64; then
    echo "Couldn't find libicu70 package for arm64"
  else
    wget https://archive.ubuntu.com/ubuntu/pool/main/i/icu/libicu70_70.1-2_amd64.deb
    EXPECTED_LIBICU_SHA512="a6315482d93606e375c272718d2458870b95e4ed4b672ea8640cf7bc2d2c2f41aea13b798b1e417e1ffc472a90c6aad150d3d293aa9bddec48e39106e4042807"
    ACTUAL_LIBICU_SHA512="$(sha512sum "./libicu70_70.1-2_amd64.deb" | awk '{print $1}')"
    [ "$EXPECTED_LIBICU_SHA512" = "$ACTUAL_LIBICU_SHA512" ] || { echo "libicu checksum mismatch in configure-dpkg.sh"; exit 1;}
    sudo apt-get install -y ./libicu70_70.1-2_amd64.deb
  fi
fi
