#!/usr/bin/env sh
#
# Install shell scripts for FreeBSD, MacOS, or Linux systems.

# Exit immediately if a command exits with non-zero return code.
#
# Flags:
#   -e: Exit immediately when a command fails.
#   -u: Throw an error when an unset variable is encountered.
set -eu

#######################################
# Show CLI help information.
# Cannot use function name help, since help is a pre-existing command.
# Outputs:
#   Writes help information to stdout.
#######################################
usage() {
  cat 1>&2 << EOF
Installer script for Shell Scripts.

Usage: install [OPTIONS] SCRIPT

Options:
      --debug               Show shell debug traces
  -d, --dest <PATH>         Directory to install scripts
  -h, --help                Print help information
  -l, --list                List all available scripts
  -u, --user                Install scripts for current user
  -v, --version <VERSION>   Version of scripts to install
EOF
}

#######################################
# Add Scripts to system path in user's shell profile.
# Globals:
#   HOME
#   PATH
#   SHELL
# Arguments:
#   Parent directory of Scripts script.
#######################################
configure_shell() {
  export_cmd="export PATH=\"${1}:\$PATH\""
  shell_name="$(basename "${SHELL}")"

  case "${shell_name}" in
    bash)
      profile="${HOME}/.bashrc"
      ;;
    zsh)
      profile="${HOME}/.zshrc"
      ;;
    fish)
      export_cmd="set -x PATH \"${1}\" \$PATH"
      profile="${HOME}/.config/fish/config.fish"
      ;;
    *)
      profile="${HOME}/.profile"
      ;;
  esac

  printf '\n# Added by Shell Scripts installer.\n%s\n' "${export_cmd}" \
    >> "${profile}"
}

#######################################
# Download file to local path.
# Arguments:
#   Super user command for installation.
#   Remote source URL.
#   Local destination path.
#######################################
download() {
  # Flags:
  #   -O path: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v curl)" ]; then
    ${1:+"${1}"} curl --fail --location --show-error --silent --output "${3}" \
      "${2}"
  else
    ${1:+"${1}"} wget -q -O "${3}" "${2}"
  fi
}

#######################################
# Download Jq binary to temporary path.
# Arguments:
#   Operating system name.
# Outputs:
#   Path to temporary Jq binary.
#######################################
download_jq() {
  # Do not use long form --machine flag for uname. It is not supported on MacOS.
  #
  # Flags:
  #   -m: Show system architecture name.
  arch="$(uname -m | sed s/x86_64/amd64/ | sed s/x64/amd64/ |
    sed s/aarch64/arm64/)"
  tmp_path="$(mktemp)"
  download '' \
    "https://github.com/jqlang/jq/releases/latest/download/jq-${1}-${arch}" \
    "${tmp_path}"
  chmod 755 "${tmp_path}"
  echo "${tmp_path}"
}

#######################################
# Print error message and exit script with error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error() {
  bold_red='\033[1;31m' default='\033[0m'
  printf "${bold_red}error${default}: %s\n" "${1}" >&2
  exit 1
}

#######################################
# Print error message and exit script with usage error code.
# Outputs:
#   Writes error message to stderr.
#######################################
error_usage() {
  bold_red='\033[1;31m' default='\033[0m'
  printf "${bold_red}error${default}: %s\n" "${1}" >&2
  printf "Run 'install --help' for usage\n" >&2
  exit 2
}

#######################################
# Find or download Jq JSON parser.
# Outputs:
#   Path to Jq binary.
#######################################
find_jq() {
  # Do not use long form --kernel-name flag for uname. It is not supported on
  # MacOS.
  #
  # Flags:
  #   -s: Show operating system kernel name.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  jq_bin="$(command -v jq || echo '')"
  if [ -x "${jq_bin}" ]; then
    echo "${jq_bin}"
  else
    case "$(uname -s)" in
      Darwin)
        download_jq macos
        ;;
      FreeBSD)
        super="$(find_super)"
        ${super:+"${super}"} pkg update > /dev/null 2>&1
        ${super:+"${super}"} pkg install --yes jq > /dev/null 2>&1
        command -v jq
        ;;
      Linux)
        download_jq linux
        ;;
      *)
        error "$(
          cat << EOF
Cannot find required 'jq' command on computer.
Please install 'jq' and retry installation.
EOF
        )"
        ;;
    esac
  fi
}

#######################################
# Find all scripts inside GitHub repository.
# Arguments:
#   Version
# Returns:
#   Array of script name stems.
#######################################
find_scripts() {
  url="https://api.github.com/repos/scruffaluff/shell-scripts/git/trees/${1}?recursive=true"

  # Flags:
  #   -O path: Save download to path.
  #   -q: Hide log output.
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ -x "$(command -v curl)" ]; then
    response="$(curl --fail --location --show-error --silent "${url}")"
  else
    response="$(wget -q -O - "${url}")"
  fi

  jq_bin="$(find_jq)"
  filter='.tree[] | select(.type == "blob") | .path | select(startswith("src/")) | select(endswith(".sh")) | ltrimstr("src/") | rtrimstr(".sh")'
  echo "${response}" | "${jq_bin}" --exit-status --raw-output "${filter}"
}

#######################################
# Find command to elevate as super user.
#######################################
find_super() {
  # Do not use long form --user flag for id. It is not supported on MacOS.
  #
  # Flags:
  #   -v: Only show file path of command.
  #   -x: Check if file exists and execute permission is granted.
  if [ "$(id -u)" -eq 0 ]; then
    echo ''
  elif [ -x "$(command -v sudo)" ]; then
    echo 'sudo'
  elif [ -x "$(command -v doas)" ]; then
    echo 'doas'
  else
    error 'Unable to find a command for super user elevation'
  fi
}

#######################################
# Print log message to stdout if logging is enabled.
# Arguments:
#   Super user command for installation
#   Script URL prefix
#   Destination path prefix
#   Script name
# Globals:
#   SHELL_SCRIPTS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
install_script() {
  dst_file="${3}/${4}"
  src_url="${2}/${4}.sh"

  # Use super user elevation command for system installation if user did not
  # give the --user, does not own the file, and is not root.
  #
  # Do not use long form --user flag for id. It is not supported on MacOS.
  #
  # Flags:
  #   -w: Check if file exists and is writable.
  #   -z: Check if the string has zero length or is null.
  if [ -z "${1}" ] && [ ! -w "${dst_file}" ]; then
    super="$(find_super)"
  else
    super=''
  fi

  log "Installing script ${4}..."

  # Do not quote the outer super parameter expansion. Shell will error due to be
  # being unable to find the "" command.
  ${super:+"${super}"} mkdir -p "${3}"
  download "${super}" "${src_url}" "${dst_file}"
  ${super:+"${super}"} chmod 755 "${dst_file}"

  # Add Scripts to shell profile if not in system path.
  #
  # Flags:
  #   -e: Check if file exists.
  #   -v: Only show file path of command.
  if [ ! -e "$(command -v "${4}")" ]; then
    configure_shell "${3}"
    export PATH="${3}:${PATH}"
  fi

  log "Installed $("${4}" --version)."
}

#######################################
# Print log message to stdout if logging is enabled.
# Globals:
#   SHELL_SCRIPTS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
log() {
  # Log if environment variable is not set.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${SHELL_SCRIPTS_NOLOG:-}" ]; then
    echo "$@"
  fi
}

#######################################
# Script entrypoint.
#######################################
main() {
  dst_dir='/usr/local/bin' names='' version='main'

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -d | --dest)
        dst_dir="${2}"
        shift 2
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -l | --list)
        list_scripts='true'
        shift 1
        ;;
      -u | --user)
        dst_dir="${HOME}/.local/bin"
        user_install='true'
        shift 1
        ;;
      -v | --version)
        version="${2}"
        shift 2
        ;;
      *)
        if [ -n "${names}" ]; then
          names="${names} ${1}"
        else
          names="${1}"
        fi
        shift 1
        ;;
    esac
  done

  src_prefix="https://raw.githubusercontent.com/scruffaluff/shell-scripts/${version}/src"
  scripts="$(find_scripts "${version}")"

  # Flags:
  #   -n: Check if the string has nonzero length.
  if [ -n "${list_scripts:-}" ]; then
    echo "${scripts}"
  else
    for name in ${names}; do
      for script in ${scripts}; do
        if [ "${script}" = "${name}" ]; then
          match_found='true'
          install_script "${user_install:-}" "${src_prefix}" "${dst_dir}" \
            "${script}"
        fi
      done
    done

    # Flags:
    #   -z: Check if string has zero length.
    if [ -z "${match_found:-}" ]; then
      error_usage "No script found for '${names}'."
    fi
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
