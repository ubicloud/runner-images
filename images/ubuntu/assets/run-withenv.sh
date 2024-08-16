#!/bin/bash -e

token="$1"
setup_info="$2"
env_variables="$3"

if [[ -z "$token" ]]; then
  echo "JIT token is required as the first argument"
  exit 1
fi

# runneradmin user on default Github hosted runners is a member of adm and
# sudo groups. Having sudo access also allows us getting journalctl logs in
# case of any issue on the destroy state below by runneradmin user.
sudo usermod -a -G sudo,adm runneradmin

if [[ -n "$setup_info" ]]; then
    # The `imagedata.json` file contains information about the generated image.
    # We enrich it with details about the Ubicloud environment and placed it in the runner's home directory.
    # GitHub-hosted runners also use this file as setup_info to show on the GitHub UI.
    jq ". += [$setup_info]" /imagegeneration/imagedata.json > /home/runner/actions-runner/.setup_info
fi

if [[ -n "$env_variables" ]]; then
    # We pass additional environment variables to the runner script.
    echo "$env_variables" | sudo tee -a /etc/environment
fi

mapfile -t env </etc/environment
exec env -- "${env[@]}" ./actions-runner/run.sh --jitconfig "$token"
