{ # this ensures the entire script is downloaded #

cortex_has() {
  type "$1" > /dev/null 2>&1
}

cortex_default_install_dir() {
  if [ -n "$XDG_CONFIG_HOME" ]; then
    printf %s "${XDG_CONFIG_HOME/cortex}"
  else
    printf %s "$HOME/.cortexbin"
  fi
}

cortex_stdout_is_terminal() {
  [ -t 1 ]
}

cortex_echo() {
  command printf %s\\n "$*" 2>/dev/null
}

cortex_check_env() {
}

cortex_cd() {
  \cd "$@"
}

cortex_err() {
  >&2 cortex_echo "$@"
}

cortex_grep() {
  GREP_OPTIONS='' command grep "$@"
}

cortex_has() {
  type "${1-}" >/dev/null 2>&1
}

cortex() {
  if [ $# -lt 1 ]; then
    cortex --help
    return
  fi

  local DEFAULT_IFS
  DEFAULT_IFS=" $(cortex_echo t | command tr t \\t)
"
  if [ "${-#*e}" != "$-" ]; then
    set +e
    local EXIT_CODE
    IFS="${DEFAULT_IFS}" cortex "$@"
    EXIT_CODE=$?
    set -e
    return $EXIT_CODE
  elif [ "${IFS}" != "${DEFAULT_IFS}" ]; then
    IFS="${DEFAULT_IFS}" cortex "$@"
    return $?
  fi

  local COMMAND
  COMMAND="${1-}"
  shift

  # initialize local variables
  local VERSION
  local ADDITIONAL_PARAMETERS

  case $COMMAND in
    'help' | '--help')
      local CORTEX_IOJS_PREFIX
      CORTEX_IOJS_PREFIX="$(cortex_iojs_prefix)"
      local CORTEX_NODE_PREFIX
      CORTEX_NODE_PREFIX="$(cortex_node_prefix)"
      CORTEX_VERSION="$(cortex --version)"
      cortex_echo
      cortex_echo "Cortex Environment Manager (v${CORTEX_VERSION})"
      cortex_echo
      cortex_echo 'Note: <version> refers to any version-like string cortex understands. This includes:'
      cortex_echo '  - full or partial version numbers, starting with an optional "v" (0.10, v0.1.2, v1)'
      cortex_echo "  - default (built-in) aliases: ${CORTEX_NODE_PREFIX}, stable, unstable, ${CORTEX_IOJS_PREFIX}, system"
      cortex_echo '  - custom aliases you define with `cortex alias foo`'
      cortex_echo
      cortex_echo ' Any options that produce colorized output should respect the `--no-colors` option.'
      cortex_echo
      cortex_echo 'Usage:'
      cortex_echo '  cortex --help                                Show this message'
      cortex_echo '  cortex --version                             Print out the installed version of cortex'
      cortex_echo '  cortex install [-s] <version>                Download and install a <version>, [-s] from source. Uses .cortexrc if available'
      cortex_echo '    --reinstall-packages-from=<version>     When installing, reinstall packages installed in <node|iojs|node version number>'
      cortex_echo '    --lts                                   When installing, only select from LTS (long-term support) versions'
      cortex_echo '    --lts=<LTS name>                        When installing, only select from versions for a specific LTS line'
      cortex_echo '    --skip-default-packages                 When installing, skip the default-packages file if it exists'
      cortex_echo '    --latest-npm                            After installing, attempt to upgrade to the latest working npm on the given node version'
      cortex_echo '    --no-progress                           Disable the progress bar on any downloads'
      cortex_echo '  cortex uninstall <version>                   Uninstall a version'
      cortex_echo
      cortex_echo 'Example:'
      cortex_echo '  cortex install 8.0.0                     Install a specific version number'
      cortex_echo '  cortex run 6.10.3 app.js                 Run app.js using node 6.10.3'
      cortex_echo
      cortex_echo 'Note:'
      cortex_echo '  to remove, delete, or uninstall cortex - just remove the `$CORTEX_DIR` folder (usually `~/.cortex`)'
      cortex_echo
    ;;

    "install" | "i")
      local version_not_provided
      version_not_provided=0
      local CORTEX_OS
      CORTEX_OS="$(cortex_get_os)"

      if ! cortex_has "curl" && ! cortex_has "wget"; then
        cortex_err 'cortex needs curl or wget to proceed.'
        return 1
      fi

      if [ $# -lt 1 ]; then
        version_not_provided=1
      fi

      local nobinary
      local noprogress
      nobinary=0
      noprogress=0
      local LTS
      local CORTEX_UPGRADE_NPM
      CORTEX_UPGRADE_NPM=0
      while [ $# -ne 0 ]; do
        case "$1" in
          ---*)
            cortex_err 'arguments with `---` are not supported - this is likely a typo'
            return 55;
          ;;
          -s)
            shift # consume "-s"
            nobinary=1
          ;;
          -j)
            shift # consume "-j"
            cortex_get_make_jobs "$1"
            shift # consume job count
          ;;
          --no-progress)
            noprogress=1
            shift
          ;;
          --lts)
            LTS='*'
            shift
          ;;
          --lts=*)
            LTS="${1##--lts=}"
            shift
          ;;
          --latest-npm)
            CORTEX_UPGRADE_NPM=1
            shift
          ;;
          *)
            break # stop parsing args
          ;;
        esac
      done

      local provided_version
      provided_version="${1-}"

      if [ -z "${provided_version}" ]; then
				return
      fi

      case "${provided_version}" in
        'lts/*')
          LTS='*'
          provided_version=''
        ;;
        lts/*)
          LTS="${provided_version##lts/}"
          provided_version=''
        ;;
      esac

      VERSION="$(CORTEX_VERSION_ONLY=true CORTEX_LTS="${LTS-}" cortex_remote_version "${provided_version}")"

      if [ "${VERSION}" = 'N/A' ]; then
        local LTS_MSG
        local REMOTE_CMD
        if [ "${LTS-}" = '*' ]; then
          LTS_MSG='(with LTS filter) '
          REMOTE_CMD='cortex ls-remote --lts'
        elif [ -n "${LTS-}" ]; then
          LTS_MSG="(with LTS filter '${LTS}') "
          REMOTE_CMD="cortex ls-remote --lts=${LTS}"
        else
          REMOTE_CMD='cortex ls-remote'
        fi
        cortex_err "Version '${provided_version}' ${LTS_MSG-}not found - try \`${REMOTE_CMD}\` to browse available versions."
        return 3
      fi

      ADDITIONAL_PARAMETERS=''
      local PROVIDED_REINSTALL_PACKAGES_FROM
      local REINSTALL_PACKAGES_FROM
      local SKIP_DEFAULT_PACKAGES
      local DEFAULT_PACKAGES

      while [ $# -ne 0 ]; do
        case "$1" in
          --reinstall-packages-from=*)
            PROVIDED_REINSTALL_PACKAGES_FROM="$(cortex_echo "$1" | command cut -c 27-)"
            if [ -z "${PROVIDED_REINSTALL_PACKAGES_FROM}" ]; then
              cortex_err 'If --reinstall-packages-from is provided, it must point to an installed version of node.'
              return 6
            fi
            REINSTALL_PACKAGES_FROM="$(cortex_version "${PROVIDED_REINSTALL_PACKAGES_FROM}")" ||:
          ;;
          --reinstall-packages-from)
            cortex_err 'If --reinstall-packages-from is provided, it must point to an installed version of node using `=`.'
            return 6
          ;;
          --copy-packages-from=*)
            PROVIDED_REINSTALL_PACKAGES_FROM="$(cortex_echo "$1" | command cut -c 22-)"
            REINSTALL_PACKAGES_FROM="$(cortex_version "${PROVIDED_REINSTALL_PACKAGES_FROM}")" ||:
          ;;
          --skip-default-packages)
            SKIP_DEFAULT_PACKAGES=true
          ;;
          *)
            ADDITIONAL_PARAMETERS="${ADDITIONAL_PARAMETERS} $1"
          ;;
        esac
        shift
      done

      if [ -z "${SKIP_DEFAULT_PACKAGES-}" ]; then
        DEFAULT_PACKAGES="$(cortex_get_default_packages)"
        EXIT_CODE=$?
        if [ $EXIT_CODE -ne 0 ]; then
          return $EXIT_CODE
        fi
      fi

      if [ -n "${PROVIDED_REINSTALL_PACKAGES_FROM-}" ] && [ "$(cortex_ensure_version_prefix "${PROVIDED_REINSTALL_PACKAGES_FROM}")" = "${VERSION}" ]; then
        cortex_err "You can't reinstall global packages from the same version of node you're installing."
        return 4
      elif [ "${REINSTALL_PACKAGES_FROM-}" = 'N/A' ]; then
        cortex_err "If --reinstall-packages-from is provided, it must point to an installed version of node."
        return 5
      fi

      local FLAVOR
      if cortex_is_iojs_version "${VERSION}"; then
        FLAVOR="$(cortex_iojs_prefix)"
      else
        FLAVOR="$(cortex_node_prefix)"
      fi

      if cortex_is_version_installed "${VERSION}"; then
        cortex_err "${VERSION} is already installed."
        if cortex use "${VERSION}"; then
          if [ "${CORTEX_UPGRADE_NPM}" = 1 ]; then
            cortex install-latest-npm
          fi
          if [ -z "${SKIP_DEFAULT_PACKAGES-}" ] && [ -n "${DEFAULT_PACKAGES-}" ]; then
            cortex_install_default_packages "${DEFAULT_PACKAGES}"
          fi
          if [ -n "${REINSTALL_PACKAGES_FROM-}" ] && [ "_${REINSTALL_PACKAGES_FROM}" != "_N/A" ]; then
            cortex reinstall-packages "${REINSTALL_PACKAGES_FROM}"
          fi
        fi
        if [ -n "${LTS-}" ]; then
          LTS="$(echo "${LTS}" | tr '[:upper:]' '[:lower:]')"
          cortex_ensure_default_set "lts/${LTS}"
        else
          cortex_ensure_default_set "${provided_version}"
        fi
        return $?
      fi

      local EXIT_CODE
      EXIT_CODE=-1
      if [ -n "${CORTEX_INSTALL_THIRD_PARTY_HOOK-}" ]; then
        cortex_err '** $CORTEX_INSTALL_THIRD_PARTY_HOOK env var set; dispatching to third-party installation method **'
        local CORTEX_METHOD_PREFERENCE
        CORTEX_METHOD_PREFERENCE='binary'
        if [ $nobinary -eq 1 ]; then
          CORTEX_METHOD_PREFERENCE='source'
        fi
        local VERSION_PATH
        VERSION_PATH="$(cortex_version_path "${VERSION}")"
        "${CORTEX_INSTALL_THIRD_PARTY_HOOK}" "${VERSION}" "${FLAVOR}" std "${CORTEX_METHOD_PREFERENCE}" "${VERSION_PATH}" || {
          EXIT_CODE=$?
          cortex_err '*** Third-party $CORTEX_INSTALL_THIRD_PARTY_HOOK env var failed to install! ***'
          return $EXIT_CODE
        }
        if ! cortex_is_version_installed "${VERSION}"; then
          cortex_err '*** Third-party $CORTEX_INSTALL_THIRD_PARTY_HOOK env var claimed to succeed, but failed to install! ***'
          return 33
        fi
        EXIT_CODE=0
      else

        if [ "_${CORTEX_OS}" = "_freebsd" ]; then
          # node.js and io.js do not have a FreeBSD binary
          nobinary=1
          cortex_err "Currently, there is no binary for FreeBSD"
        elif [ "_${CORTEX_OS}" = "_sunos" ]; then
          # Not all node/io.js versions have a Solaris binary
          if ! cortex_has_solaris_binary "${VERSION}"; then
            nobinary=1
            cortex_err "Currently, there is no binary of version ${VERSION} for SunOS"
          fi
        fi

        # skip binary install if "nobinary" option specified.
        if [ $nobinary -ne 1 ] && cortex_binary_available "${VERSION}"; then
          CORTEX_NO_PROGRESS="${CORTEX_NO_PROGRESS:-${noprogress}}" cortex_install_binary "${FLAVOR}" std "${VERSION}"
          EXIT_CODE=$?
        fi
        if [ $EXIT_CODE -ne 0 ]; then
          if [ -z "${CORTEX_MAKE_JOBS-}" ]; then
            cortex_get_make_jobs
          fi

          CORTEX_NO_PROGRESS="${CORTEX_NO_PROGRESS:-${noprogress}}" cortex_install_source "${FLAVOR}" std "${VERSION}" "${CORTEX_MAKE_JOBS}" "${ADDITIONAL_PARAMETERS}"
          EXIT_CODE=$?
        fi

      fi

      if [ $EXIT_CODE -eq 0 ] && cortex_use_if_needed "${VERSION}" && cortex_install_npm_if_needed "${VERSION}"; then
        if [ -n "${LTS-}" ]; then
          cortex_ensure_default_set "lts/${LTS}"
        else
          cortex_ensure_default_set "${provided_version}"
        fi
        if [ "${CORTEX_UPGRADE_NPM}" = 1 ]; then
          cortex install-latest-npm
          EXIT_CODE=$?
        fi
        if [ -z "${SKIP_DEFAULT_PACKAGES-}" ] && [ -n "${DEFAULT_PACKAGES-}" ]; then
          cortex_install_default_packages "${DEFAULT_PACKAGES}"
        fi
        if [ -n "${REINSTALL_PACKAGES_FROM-}" ] && [ "_${REINSTALL_PACKAGES_FROM}" != "_N/A" ]; then
          cortex reinstall-packages "${REINSTALL_PACKAGES_FROM}"
          EXIT_CODE=$?
        fi
      else
        EXIT_CODE=$?
      fi
      return $EXIT_CODE
    ;;
    "uninstall")
      if [ $# -ne 1 ]; then
        >&2 cortex --help
        return 127
      fi

      local PATTERN
      PATTERN="${1-}"
      case "${PATTERN-}" in
        --) ;;
        --lts | 'lts/*')
          VERSION="$(cortex_match_version "lts/*")"
        ;;
        lts/*)
          VERSION="$(cortex_match_version "lts/${PATTERN##lts/}")"
        ;;
        --lts=*)
          VERSION="$(cortex_match_version "lts/${PATTERN##--lts=}")"
        ;;
        *)
          VERSION="$(cortex_version "${PATTERN}")"
        ;;
      esac

      if [ "_${VERSION}" = "_$(cortex_ls_current)" ]; then
        if cortex_is_iojs_version "${VERSION}"; then
          cortex_err "cortex: Cannot uninstall currently-active io.js version, ${VERSION} (inferred from ${PATTERN})."
        else
          cortex_err "cortex: Cannot uninstall currently-active node version, ${VERSION} (inferred from ${PATTERN})."
        fi
        return 1
      fi

      if ! cortex_is_version_installed "${VERSION}"; then
        cortex_err "${VERSION} version is not installed..."
        return
      fi

      local SLUG_BINARY
      local SLUG_SOURCE
      if cortex_is_iojs_version "${VERSION}"; then
        SLUG_BINARY="$(cortex_get_download_slug iojs binary std "${VERSION}")"
        SLUG_SOURCE="$(cortex_get_download_slug iojs source std "${VERSION}")"
      else
        SLUG_BINARY="$(cortex_get_download_slug node binary std "${VERSION}")"
        SLUG_SOURCE="$(cortex_get_download_slug node source std "${VERSION}")"
      fi

      local CORTEX_SUCCESS_MSG
      if cortex_is_iojs_version "${VERSION}"; then
        CORTEX_SUCCESS_MSG="Uninstalled io.js $(cortex_strip_iojs_prefix "${VERSION}")"
      else
        CORTEX_SUCCESS_MSG="Uninstalled node ${VERSION}"
      fi

      local VERSION_PATH
      VERSION_PATH="$(cortex_version_path "${VERSION}")"
      if ! cortex_check_file_permissions "${VERSION_PATH}"; then
        cortex_err 'Cannot uninstall, incorrect permissions on installation folder.'
        cortex_err 'This is usually caused by running `npm install -g` as root. Run the following commands as root to fix the permissions and then try again.'
        cortex_err
        cortex_err "  chown -R $(whoami) \"$(cortex_sanitize_path "${VERSION_PATH}")\""
        cortex_err "  chmod -R u+w \"$(cortex_sanitize_path "${VERSION_PATH}")\""
        return 1
      fi

      # Delete all files related to target version.
      local CACHE_DIR
      CACHE_DIR="$(cortex_cache_dir)"
      command rm -rf \
        "${CACHE_DIR}/bin/${SLUG_BINARY}/files" \
        "${CACHE_DIR}/src/${SLUG_SOURCE}/files" \
        "${VERSION_PATH}" 2>/dev/null
      cortex_echo "${CORTEX_SUCCESS_MSG}"

      # rm any aliases that point to uninstalled version.
      for ALIAS in $(cortex_grep -l "${VERSION}" "$(cortex_alias_path)/*" 2>/dev/null); do
        cortex unalias "$(command basename "${ALIAS}")"
      done
    ;;
    "deactivate")
      local NEWPATH
      NEWPATH="$(cortex_strip_path "${PATH}" "/bin")"
      if [ "_${PATH}" = "_${NEWPATH}" ]; then
        cortex_err "Could not find ${CORTEX_DIR}/*/bin in \${PATH}"
      else
        export PATH="${NEWPATH}"
        hash -r
        cortex_echo "${CORTEX_DIR}/*/bin removed from \${PATH}"
      fi

      if [ -n "${MANPATH-}" ]; then
        NEWPATH="$(cortex_strip_path "${MANPATH}" "/share/man")"
        if [ "_${MANPATH}" = "_${NEWPATH}" ]; then
          cortex_err "Could not find ${CORTEX_DIR}/*/share/man in \${MANPATH}"
        else
          export MANPATH="${NEWPATH}"
          cortex_echo "${CORTEX_DIR}/*/share/man removed from \${MANPATH}"
        fi
      fi

      if [ -n "${NODE_PATH-}" ]; then
        NEWPATH="$(cortex_strip_path "${NODE_PATH}" "/lib/node_modules")"
        if [ "_${NODE_PATH}" != "_${NEWPATH}" ]; then
          export NODE_PATH="${NEWPATH}"
          cortex_echo "${CORTEX_DIR}/*/lib/node_modules removed from \${NODE_PATH}"
        fi
      fi
      unset CORTEX_BIN
    ;;
    "run")
      local provided_version
      local has_checked_cortexrc
      has_checked_cortexrc=0
      # run given version of node

      local CORTEX_SILENT
      local CORTEX_LTS
      while [ $# -gt 0 ]; do
        case "$1" in
          --silent) CORTEX_SILENT='--silent' ; shift ;;
          --lts) CORTEX_LTS='*' ; shift ;;
          --lts=*) CORTEX_LTS="${1##--lts=}" ; shift ;;
          *)
            if [ -n "$1" ]; then
              break
            else
              shift
            fi
          ;; # stop processing arguments
        esac
      done

      if [ $# -lt 1 ] && [ -z "${CORTEX_LTS-}" ]; then
        if [ -n "${CORTEX_SILENT-}" ]; then
          cortex_rc_version >/dev/null 2>&1 && has_checked_cortexrc=1
        else
          cortex_rc_version && has_checked_cortexrc=1
        fi
        if [ -n "${CORTEX_RC_VERSION-}" ]; then
          VERSION="$(cortex_version "${CORTEX_RC_VERSION-}")" ||:
        fi
        unset CORTEX_RC_VERSION
        if [ "${VERSION:-N/A}" = 'N/A' ]; then
          >&2 cortex --help
          return 127
        fi
      fi

      if [ -z "${CORTEX_LTS-}" ]; then
        provided_version="$1"
        if [ -n "${provided_version}" ]; then
          VERSION="$(cortex_version "${provided_version}")" ||:
          if [ "_${VERSION:-N/A}" = '_N/A' ] && ! cortex_is_valid_version "${provided_version}"; then
            provided_version=''
            if [ $has_checked_cortexrc -ne 1 ]; then
              if [ -n "${CORTEX_SILENT-}" ]; then
                cortex_rc_version >/dev/null 2>&1 && has_checked_cortexrc=1
              else
                cortex_rc_version && has_checked_cortexrc=1
              fi
            fi
            VERSION="$(cortex_version "${CORTEX_RC_VERSION}")" ||:
            unset CORTEX_RC_VERSION
          else
            shift
          fi
        fi
      fi

      local CORTEX_IOJS
      if cortex_is_iojs_version "${VERSION}"; then
        CORTEX_IOJS=true
      fi

      local EXIT_CODE

      cortex_is_zsh && setopt local_options shwordsplit
      local LTS_ARG
      if [ -n "${CORTEX_LTS-}" ]; then
        LTS_ARG="--lts=${CORTEX_LTS-}"
        VERSION=''
      fi
      if [ "_${VERSION}" = "_N/A" ]; then
        cortex_ensure_version_installed "${provided_version}"
      elif [ "${CORTEX_IOJS}" = true ]; then
        cortex exec "${CORTEX_SILENT-}" "${LTS_ARG-}" "${VERSION}" iojs "$@"
      else
        cortex exec "${CORTEX_SILENT-}" "${LTS_ARG-}" "${VERSION}" node "$@"
      fi
      EXIT_CODE="$?"
      return $EXIT_CODE
    ;;
    "ls" | "list")
      local PATTERN
      local CORTEX_NO_COLORS
      local CORTEX_NO_ALIAS
      while [ $# -gt 0 ]; do
        case "${1}" in
          --) ;;
          --no-colors) CORTEX_NO_COLORS="${1}" ;;
          --no-alias) CORTEX_NO_ALIAS="${1}" ;;
          --*)
            cortex_err "Unsupported option \"${1}\"."
            return 55
          ;;
          *)
            PATTERN="${PATTERN:-$1}"
          ;;
        esac
        shift
      done
      if [ -n "${PATTERN-}" ] && [ -n "${CORTEX_NO_ALIAS}" ]; then
        cortex_err '`--no-alias` is not supported when a pattern is provided.'
        return 55
      fi
      local CORTEX_LS_OUTPUT
      local CORTEX_LS_EXIT_CODE
      CORTEX_LS_OUTPUT=$(cortex_ls "${PATTERN-}")
      CORTEX_LS_EXIT_CODE=$?
      CORTEX_NO_COLORS="${CORTEX_NO_COLORS-}" cortex_print_versions "${CORTEX_LS_OUTPUT}"
      if [ -z "${CORTEX_NO_ALIAS-}" ] && [ -z "${PATTERN-}" ]; then
        if [ -n "${CORTEX_NO_COLORS-}" ]; then
          cortex alias --no-colors
        else
          cortex alias
        fi
      fi
      return $CORTEX_LS_EXIT_CODE
    ;;
    "which")
      local provided_version
      provided_version="${1-}"
      if [ $# -eq 0 ]; then
        cortex_rc_version
        if [ -n "${CORTEX_RC_VERSION}" ]; then
          provided_version="${CORTEX_RC_VERSION}"
          VERSION=$(cortex_version "${CORTEX_RC_VERSION}") ||:
        fi
        unset CORTEX_RC_VERSION
      elif [ "_${1}" != '_system' ]; then
        VERSION="$(cortex_version "${provided_version}")" ||:
      else
        VERSION="${1-}"
      fi
      if [ -z "${VERSION}" ]; then
        >&2 cortex --help
        return 127
      fi

      if [ "_${VERSION}" = '_system' ]; then
        if cortex_has_system_iojs >/dev/null 2>&1 || cortex_has_system_node >/dev/null 2>&1; then
          local CORTEX_BIN
          CORTEX_BIN="$(cortex use system >/dev/null 2>&1 && command which node)"
          if [ -n "${CORTEX_BIN}" ]; then
            cortex_echo "${CORTEX_BIN}"
            return
          fi
          return 1
        fi
        cortex_err 'System version of node not found.'
        return 127
      elif [ "_${VERSION}" = "_∞" ]; then
        cortex_err "The alias \"$2\" leads to an infinite loop. Aborting."
        return 8
      fi

      cortex_ensure_version_installed "${provided_version}"
      EXIT_CODE=$?
      if [ "${EXIT_CODE}" != "0" ]; then
        return $EXIT_CODE
      fi
      local CORTEX_VERSION_DIR
      CORTEX_VERSION_DIR="$(cortex_version_path "${VERSION}")"
      cortex_echo "${CORTEX_VERSION_DIR}/bin/node"
    ;;
    "clean")
      command rm -f "${CORTEX_DIR}/v*" "$(cortex_version_dir)" 2>/dev/null
      cortex_echo 'cortex cache cleared.'
    ;;
  esac
}

cortex_auto() {
  local CORTEX_CURRENT
  CORTEX_CURRENT="$(cortex_ls_current)"
  local CORTEX_MODE
  CORTEX_MODE="${1-}"
  local VERSION
  if [ "_${CORTEX_MODE}" = '_install' ]; then
    VERSION="$(cortex_alias default 2>/dev/null || cortex_echo)"
    if [ -n "${VERSION}" ]; then
      cortex install "${VERSION}" >/dev/null
    elif cortex_rc_version >/dev/null 2>&1; then
      cortex install >/dev/null
    fi
  elif [ "_$CORTEX_MODE" = '_use' ]; then
    if [ "_${CORTEX_CURRENT}" = '_none' ] || [ "_${CORTEX_CURRENT}" = '_system' ]; then
      VERSION="$(cortex_resolve_local_alias default 2>/dev/null || cortex_echo)"
      if [ -n "${VERSION}" ]; then
        cortex use --silent "${VERSION}" >/dev/null
      elif cortex_rc_version >/dev/null 2>&1; then
        cortex use --silent >/dev/null
      fi
    else
      cortex use --silent "${CORTEX_CURRENT}" >/dev/null
    fi
  elif [ "_${CORTEX_MODE}" != '_none' ]; then
    cortex_err 'Invalid auto mode supplied.'
    return 1
  fi
}

cortex_process_parameters() {
  local CORTEX_AUTO_MODE
  CORTEX_AUTO_MODE='use'
  if cortex_supports_source_options; then
    while [ $# -ne 0 ]; do
      case "$1" in
        --install) CORTEX_AUTO_MODE='install' ;;
        --no-use) CORTEX_AUTO_MODE='none' ;;
      esac
      shift
    done
  fi
  cortex_auto "${CORTEX_AUTO_MODE}"
}

cortex_process_parameters "$@"

} # this ensures the entire script is downloaded #
