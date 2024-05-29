#!/usr/bin/env sh
#
# Install Deno apps for FreeBSD, MacOS, or Linux systems.

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
Installer script for Deno apps.

Usage: install [OPTIONS] APP

Options:
      --debug               Show shell debug traces
  -h, --help                Print help information
  -l, --list                List all available apps
  -u, --user                Install apps for current user
  -v, --version <VERSION>   Version of apps to install
EOF
}

#######################################
# Capitalize app name.
# Arguments:
#   Application script name.
# Outputs:
#   Application desktop name.
#######################################
capitalize() {
  case "$(uname -s)" in
    Darwin)
      # MacOS specific case is necessary since builtin sed does not support
      # changing character case. AWK solution taken from
      # https://stackoverflow.com/a/31972726.
      echo "${1}" | sed 's/_/ /g' | awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1'
      ;;
    *)
      echo "${1}" | sed 's/_/ /g' | sed 's/[^ ]*/\u&/g'
      ;;
  esac
}

#######################################
# Download file to local path.
# Arguments:
#   Super user command for installation.
#   Remote source URL.
#   Local destination path.
#   Optional permissions for file.
#######################################
download() {
  # Create parent directory if it does not exist.
  folder="$(dirname "${3}")"
  if [ ! -d "${folder}" ]; then
    ${1:+"${1}"} mkdir -p "${folder}"
  fi

  # Download with Curl or Wget.
  #
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

  # Change file permissions if chmod parameter was passed.
  if [ -n "${4:-}" ]; then
    ${1:+"${1}"} chmod "${4}" "${3}"
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
# Find all apps inside GitHub repository.
# Arguments:
#   Version
# Returns:
#   Array of app name stems.
#######################################
find_apps() {
  url="https://api.github.com/repos/scruffaluff/deno-apps/git/trees/${1}?recursive=true"

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
  filter='.tree[] | select(.type == "blob") | .path | select(startswith("src/")) | select(endswith(".ts")) | ltrimstr("src/") | rtrimstr(".ts")'
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
# Install application.
# Arguments:
#   Super user command for installation
#   App URL prefix
#   App name
# Globals:
#   DENO_APPS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
install_app() {
  # Use super user elevation command for system installation if user did not
  # give the --user, does not own the file, and is not root.
  #
  # Do not use long form --user flag for id. It is not supported on MacOS.
  #
  # Flags:
  #   -w: Check if file exists and is writable.
  #   -z: Check if the string has zero length or is null.
  if [ -z "${1}" ]; then
    super="$(find_super)"
  else
    super=''
  fi

  log "Installing app ${3}..."

  # Do not use long form --kernel-name flag for uname. It is not supported on
  # MacOS.
  os_type="$(uname -s)"
  case "${os_type}" in
    Darwin)
      install_app_macos "${super}" "${2}" "${3}"
      ;;
    Linux)
      install_app_linux "${super}" "${2}" "${3}"
      ;;
    *)
      error "Operating system ${os_type} is not supported"
      ;;
  esac

  log "Installed $(capitalize "${3}")"
}

#######################################
# Install application for Linux.
# Arguments:
#   Super user command for installation
#   App URL prefix
#   App name
# Globals:
#   DENO_APPS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
install_app_linux() {
  app_url="${2}/${3}.ts" main_url="${2}/main.sh" name="${3}" super="${1}"
  icon_url='https://uxwing.com/wp-content/themes/uxwing/download/animals-and-birds/andesaurus-dinosaur-color-icon.png'

  if [ -n "${super}" ]; then
    app_path="/usr/local/deno-apps/${name}/index.ts"
    manifest_path="/usr/local/share/applications/${3}.desktop"
    icon_path="/usr/local/deno-apps/${name}/icon.png"
    main_path="/usr/local/deno-apps/${name}/main.sh"

    download "${super}" "${app_url}" "${app_path}" 755
    download "${super}" "${icon_url}" "${icon_path}"
  else
    app_path="${HOME}/.local/deno-apps/${name}/index.ts"
    manifest_path="${HOME}/.local/share/applications/${3}.desktop"
    icon_path="${HOME}/.local/deno-apps/${name}/icon.png"
    main_path="${HOME}/.local/deno-apps/${name}/main.sh"

    download '' "${app_url}" "${app_path}" 755
    download '' "${icon_url}" "${icon_path}"
  fi

  cat << EOF | sudo tee "${manifest_path}" > /dev/null
[Desktop Entry]
Exec=${main_path}
Icon=${icon_path}
Name=$(capitalize "${name}")
Terminal=false
Type=Application
EOF
}

#######################################
# Install application for Linux.
# Arguments:
#   Super user command for installation
#   App URL prefix
#   App name
# Globals:
#   DENO_APPS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
install_app_macos() {
  app_url="${2}/${3}.ts" main_url="${2}/main.sh" name="${3}" super="${1}"
  icon_url='https://uxwing.com/wp-content/themes/uxwing/download/animals-and-birds/andesaurus-dinosaur-color-icon.png'
  identifier="com.scruffaluff.deno-app-$(echo "${name}" | sed 's/_/-/g')"
  title=$(capitalize "${name}")

  if [ -n "${super}" ]; then
    app_path="/Applications/${title}.app/Contents/MacOS/index.ts"
    manifest_path="/Applications/${title}.app/Contents/Info.plist"
    icon_path="/Applications/${title}.app/Contents/Resources/icon.png"
    main_path="/Applications/${title}.app/Contents/MacOS/main.sh"

    download "${super}" "${app_url}" "${app_path}" 755
    download "${super}" "${main_url}" "${main_path}" 755
    download "${super}" "${icon_url}" "${icon_path}"
  else
    app_path="${HOME}/Applications/${title}.app/Contents/MacOS/index.ts"
    manifest_path="${HOME}/Applications/${title}.app/Contents/Info.plist"
    icon_path="${HOME}/Applications/${title}.app/Contents/Resources/icon.png"
    main_path="${HOME}/Applications/${title}.app/Contents/MacOS/main.sh"

    download '' "${app_url}" "${app_path}" 755
    download '' "${main_url}" "${main_path}" 755
    download '' "${icon_url}" "${icon_path}"
  fi

  cat << EOF | sudo tee "${manifest_path}" > /dev/null
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>English</string>
	<key>CFBundleDisplayName</key>
	<string>${title}</string>
	<key>CFBundleExecutable</key>
	<string>main.sh</string>
  <key>CFBundleIconFile</key>
  <string>icon</string>
	<key>CFBundleIdentifier</key>
	<string>${identifier}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${name}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1.0</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
	<key>CSResourcesFileMapped</key>
	<true/>
	<key>LSMinimumSystemVersion</key>
	<string>10.13</string>
	<key>LSRequiresCarbon</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
EOF

  cat << EOF | sudo tee "${main_path}" > /dev/null
#!/usr/bin/env sh

cd "$(dirname "$(realpath "${0}")")"
./index.ts
EOF
}

#######################################
# Print log message to stdout if logging is enabled.
# Globals:
#   DENO_APPS_NOLOG
# Outputs:
#   Log message to stdout.
#######################################
log() {
  # Log if environment variable is not set.
  #
  # Flags:
  #   -z: Check if string has zero length.
  if [ -z "${DENO_APPS_NOLOG:-}" ]; then
    echo "$@"
  fi
}

#######################################
# Script entrypoint.
#######################################
main() {
  names='' version='main'

  # Parse command line arguments.
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --debug)
        set -o xtrace
        shift 1
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      -l | --list)
        list_apps='true'
        shift 1
        ;;
      -u | --user)
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

  src_prefix="https://raw.githubusercontent.com/scruffaluff/deno-apps/${version}/src"
  apps="$(find_apps "${version}")"

  # Flags:
  #   -n: Check if the string has nonzero length.
  if [ -n "${list_apps:-}" ]; then
    echo "${apps}"
  else
    for name in ${names}; do
      for app in ${apps}; do
        if [ "${app}" = "${name}" ]; then
          match_found='true'
          install_app "${user_install:-}" "${src_prefix}" "${app}"
        fi
      done
    done

    # Flags:
    #   -z: Check if string has zero length.
    if [ -z "${match_found:-}" ]; then
      error_usage "No app found for '${names}'."
    fi
  fi
}

# Add ability to selectively skip main function during test suite.
if [ -z "${BATS_SOURCE_ONLY:-}" ]; then
  main "$@"
fi
