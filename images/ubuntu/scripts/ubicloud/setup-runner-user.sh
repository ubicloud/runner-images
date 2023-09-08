#!/bin/bash -xe

# Since standard Github runners have both runneradmin and runner users
# VMs of github runners are created with runneradmin user. Adding
# runner user and group with the same id and gid as the standard.
addgroup --gid 1001 runner
adduser --disabled-password --uid 1001 --gid 1001 --gecos '' runner
echo 'runner ALL=(ALL) NOPASSWD:ALL' | sudo tee /etc/sudoers.d/98-runner

# runner unix user needed access to manipulate the Docker daemon.
# Default GitHub hosted runners have additional adm,systemd-journal groups.
usermod -a -G docker,adm,systemd-journal runner

# Some configuration files such as $PATH related to the user's home directory
# need to be changed. GitHub recommends to run post-generation scripts after
# initial boot.
# The important point, scripts use latest record at /etc/passwd as default user.
# So we need to run these scripts before bootstrap_rhizome to use runner user,
# instead of rhizome user.
# https://github.com/actions/runner-images/blob/main/docs/create-image-and-azure-resources.md#post-generation-scripts
sudo su -c "find /opt/post-generation -mindepth 1 -maxdepth 1 -type f -name '*.sh' -exec bash {} ';'"

# Post-generation scripts write some variables at /etc/environment file.
# We need to reload environment variables again.
source /etc/environment

# We placed the script in the "/usr/local/share/" directory while generating
# the golden image. However, it needs to be moved to the home directory because
# the runner creates some configuration files at the script location. Since the
# github runner vm is created with the runneradmin user, directory is first moved
# to runneradmin user's home directory. At the end of this script, it will be moved
# to runner user's home folder. We are checking first whether actions-runner exists
# under "usr/local/share to make sure that the script can be run multiple times idempotently.

cp -R /usr/local/share/actions-runner ./
chown -R packer:packer actions-runner

# ./env.sh sets some variables for runner to run properly
./actions-runner/env.sh

# Include /etc/environment in the runneradmin environment to move it to the
# runner environment at the end of this script, it's otherwise ignored, and
# this omission has caused problems.
# See https://github.com/actions/runner/issues/1703
cat <<EOT > ./actions-runner/run-withenv.sh
#!/bin/bash
mapfile -t env </etc/environment
exec env -- "\${env[@]}" ./actions-runner/run.sh --jitconfig "\$1"
EOT
chmod +x ./actions-runner/run-withenv.sh

# runner script doesn't use global $PATH variable by default. It gets path from
# secure_path at /etc/sudoers. Also script load .env file, so we are able to
# overwrite default path value of runner script with $PATH.
# https://github.com/microsoft/azure-pipelines-agent/issues/3461
echo "PATH=$PATH" >> ./actions-runner/.env

mv ./actions-runner /home/runner/
chown -R runner:runner /home/runner/actions-runner
