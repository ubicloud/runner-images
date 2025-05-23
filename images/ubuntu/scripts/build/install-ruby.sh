#!/bin/bash -e
################################################################################
##  File:  install-ruby.sh
##  Desc:  Install Ruby requirements and ruby gems
################################################################################

# Source the helpers for use with the script
source $HELPER_SCRIPTS/os.sh
source $HELPER_SCRIPTS/install.sh

apt-get install ruby-full

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
    if [[ -z "$package_tar_name" ]]; then
        echo "Package for Ruby ${toolset_version} on Ubuntu ${platform_version} was not found. Skipping this version."
        continue
    fi
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
