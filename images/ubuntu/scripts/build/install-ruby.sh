#!/bin/bash -e
################################################################################
##  File:  install-ruby.sh
##  Desc:  Install Ruby requirements and ruby gems
################################################################################

# Source the helpers for use with the script
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/install.sh

apt-get install ruby-full

# temporary fix for fastlane installation https://github.com/sporkmonger/addressable/issues/541
if is_ubuntu20; then

    gem install public_suffix -v 5.1.1
    
    # Install google-cloud-errors gem pinned to version 1.4.0
    gem install google-cloud-errors -v 1.4.0

    # Install faraday-net_http gem pinned to version 3.0.2
    gem install faraday-net_http -v 3.0.2

    # Install faraday gem pinned to version 2.8.1
    gem install faraday -v 2.8.1

    # Install google-cloud-env gem pinned to version 2.1.1
    gem install google-cloud-env -v 2.1.1

    # Install google-cloud-core gem pinned to version 1.7.1
    gem install google-cloud-core -v 1.7.1
fi

# Install ruby gems from toolset
gems_to_install=$(get_toolset_value ".rubygems[] .name")
if [[ -n "$gems_to_install" ]]; then
    for gem in $gems_to_install; do
        echo "Installing gem $gem"
        gem install --no-document $gem
    done
fi

# Install Ruby requirements
apt-get install libz-dev openssl libssl-dev

echo "Install Ruby from toolset..."
package_tar_names=$(curl -fsSL "https://api.github.com/repos/ruby/ruby-builder/releases/latest" | jq -r '.assets[].name')
toolset_versions=$(get_toolset_value '.toolcache[] | select(.name | contains("Ruby")) | .versions[]')
platform_version=$(get_toolset_value '.toolcache[] | select(.name | contains("Ruby")) | .platform_version')
ruby_path="$AGENT_TOOLSDIRECTORY/Ruby"

echo "Check if Ruby hostedtoolcache folder exist..."
if [[ ! -d $ruby_path ]]; then
    mkdir -p $ruby_path
fi

if is_arm64; then
    git clone https://github.com/rbenv/ruby-build.git
    ./ruby-build/install.sh
fi

for toolset_version in ${toolset_versions[@]}; do
    package_tar_name=$(echo "$package_tar_names" | grep "^ruby-${toolset_version}-ubuntu-${platform_version}.tar.gz$" | sort -V | tail -1)
    ruby_version=$(echo "$package_tar_name" | cut -d'-' -f 2)
    ruby_version_path="$ruby_path/$ruby_version"

    echo "Create Ruby $ruby_version directory..."
    mkdir -p $ruby_version_path

    if is_arm64; then
        ruby-build "$ruby_version" "$ruby_version_path/arm64"
    else
        echo "Downloading tar archive $package_tar_name"
        download_url="https://github.com/ruby/ruby-builder/releases/download/toolcache/${package_tar_name}"
        package_archive_path=$(download_with_retry "$download_url")

        echo "Expand '$package_tar_name' to the '$ruby_version_path' folder"
        tar xf "$package_archive_path" -C $ruby_version_path
    fi

    complete_file_path="$ruby_version_path/$(get_arch "x64" "arm64").complete"
    if [[ ! -f $complete_file_path ]]; then
        echo "Create complete file"
        touch $complete_file_path
    fi
done

if is_arm64; then
    rm -rf ruby-build
fi

invoke_tests "Tools" "Ruby"
