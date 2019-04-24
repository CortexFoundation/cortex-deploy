#!/usr/bin/env bash

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

cortex_install_dir() {
  if [ -n "$CORTEX_DIR" ]; then
    printf %s "${CORTEX_DIR}"
  else
    cortex_default_install_dir
  fi
}

cortex_latest_version() {
  echo "master"
}

cortex_profile_is_bash_or_zsh() {
  local TEST_PROFILE
  TEST_PROFILE="${1-}"
  case "${TEST_PROFILE-}" in
    *"/.bashrc" | *"/.bash_profile" | *"/.zshrc")
      return
    ;;
    *)
      return 1
    ;;
  esac
}

#
# Outputs the location to CORTEX depending on:
# * The availability of $CORTEX_SOURCE
# * The method used ("script" or "git" in the script, defaults to "git")
# CORTEX_SOURCE always takes precedence unless the method is "script-cortex-exec"
#
cortex_source() {
  local CORTEX_METHOD
  CORTEX_METHOD="$1"
  local CORTEX_SOURCE_URL
  CORTEX_SOURCE_URL="$CORTEX_SOURCE"
  if [ "_$CORTEX_METHOD" = "_script-cortex-bash-completion" ]; then
    CORTEX_SOURCE_URL="https://raw.githubusercontent.com/CortexFoundation/cortex-deploy/$(cortex_latest_version)/bash_completion"
  elif [ -z "$CORTEX_SOURCE_URL" ]; then
    if [ "_$CORTEX_METHOD" = "_script" ]; then
      CORTEX_SOURCE_URL="https://raw.githubusercontent.com/CortexFoundation/cortex-deploy/$(cortex_latest_version)/cortex.sh"
    elif [ "_$CORTEX_METHOD" = "_git" ] || [ -z "$CORTEX_METHOD" ]; then
      CORTEX_SOURCE_URL="https://github.com/CortexFoundation/cortex-deploy.git"
    else
      echo >&2 "Unexpected value \"$CORTEX_METHOD\" for \$CORTEX_METHOD"
      return 1
    fi
  fi
  echo "$CORTEX_SOURCE_URL"
}

#
# Cortex version to install
#
cortex_node_version() {
  echo "$NODE_VERSION"
}

cortex_download() {
  if cortex_has "curl"; then
    curl --compressed -q "$@"
  elif cortex_has "wget"; then
    # Emulate curl with wget
    ARGS=$(echo "$*" | command sed -e 's/--progress-bar /--progress=bar /' \
                            -e 's/-L //' \
                            -e 's/--compressed //' \
                            -e 's/-I /--server-response /' \
                            -e 's/-s /-q /' \
                            -e 's/-o /-O /' \
                            -e 's/-C - /-c /')
    # shellcheck disable=SC2086
    eval wget $ARGS
  fi
}

install_cortex_from_git() {
  local INSTALL_DIR
  INSTALL_DIR="$(cortex_install_dir)"

  if [ -d "$INSTALL_DIR/.git" ]; then
    echo "=> cortex is already installed in $INSTALL_DIR, trying to update using git"
    command printf '\r=> '
    command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" fetch origin tag "$(cortex_latest_version)" --depth=1 2> /dev/null || {
      echo >&2 "Failed to update cortex, run 'git fetch' in $INSTALL_DIR yourself."
      exit 1
    }
  else
    # Cloning to $INSTALL_DIR
    echo "=> Downloading cortex from git to '$INSTALL_DIR'"
    command printf '\r=> '
    mkdir -p "${INSTALL_DIR}"
    if [ "$(ls -A "${INSTALL_DIR}")" ]; then
      command git init "${INSTALL_DIR}" || {
        echo >&2 'Failed to initialize cortex repo. Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" remote add origin "$(cortex_source)" 2> /dev/null \
        || command git --git-dir="${INSTALL_DIR}/.git" remote set-url origin "$(cortex_source)" || {
        echo >&2 'Failed to add remote "origin" (or set the URL). Please report this!'
        exit 2
      }
      command git --git-dir="${INSTALL_DIR}/.git" fetch origin tag "$(cortex_latest_version)" --depth=1 || {
        echo >&2 'Failed to fetch origin with tags. Please report this!'
        exit 2
      }
    else
      command git -c advice.detachedHead=false clone "$(cortex_source)" -b "$(cortex_latest_version)" --depth=1 "${INSTALL_DIR}" || {
        echo >&2 'Failed to clone cortex repo. Please report this!'
        exit 2
      }
    fi
  fi
  command git -c advice.detachedHead=false --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" checkout -f --quiet "$(cortex_latest_version)"
  if [ -n "$(command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" show-ref refs/heads/master)" ]; then
    if command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet 2>/dev/null; then
      command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch --quiet -D master >/dev/null 2>&1
    else
      echo >&2 "Your version of git is out of date. Please update it!"
      command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" branch -D master >/dev/null 2>&1
    fi
  fi

  echo "=> Compressing and cleaning up git repository"
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" reflog expire --expire=now --all; then
    echo >&2 "Your version of git is out of date. Please update it!"
  fi
  if ! command git --git-dir="$INSTALL_DIR"/.git --work-tree="$INSTALL_DIR" gc --auto --aggressive --prune=now ; then
    echo >&2 "Your version of git is out of date. Please update it!"
  fi
  return
}

#
# Automatically install Cortex
#
cortex_install_node() {
  local NODE_VERSION_LOCAL
  NODE_VERSION_LOCAL="$(cortex_node_version)"

  if [ -z "$NODE_VERSION_LOCAL" ]; then
    return 0
  fi

  echo "=> Installing Cortex version $NODE_VERSION_LOCAL"
  cortex install "$NODE_VERSION_LOCAL"
  local CURRENT_CORTEX_NODE

  CURRENT_CORTEX_NODE="$(cortex_version current)"
  if [ "$(cortex_version "$NODE_VERSION_LOCAL")" == "$CURRENT_CORTEX_NODE" ]; then
    echo "=> Cortex version $NODE_VERSION_LOCAL has been successfully installed"
  else
    echo >&2 "Failed to install Cortex $NODE_VERSION_LOCAL"
  fi
}

install_cortex_as_script() {
  local INSTALL_DIR
  INSTALL_DIR="$(cortex_install_dir)"
  local CORTEX_SOURCE_LOCAL
  CORTEX_SOURCE_LOCAL="$(cortex_source script)"
  local CORTEX_BASH_COMPLETION_SOURCE
  CORTEX_BASH_COMPLETION_SOURCE="$(cortex_source script-cortex-bash-completion)"

  # Downloading to $INSTALL_DIR
  mkdir -p "$INSTALL_DIR"
  if [ -f "$INSTALL_DIR/cortex.sh" ]; then
    echo "=> cortex is already installed in $INSTALL_DIR, trying to update the script"
  else
    echo "=> Downloading cortex as script to '$INSTALL_DIR'"
  fi
  cortex_download -s "$CORTEX_SOURCE_LOCAL" -o "$INSTALL_DIR/cortex.sh" || {
    echo >&2 "Failed to download '$CORTEX_SOURCE_LOCAL'"
    return 1
  } &
  cortex_download -s "$CORTEX_BASH_COMPLETION_SOURCE" -o "$INSTALL_DIR/bash_completion" || {
    echo >&2 "Failed to download '$CORTEX_BASH_COMPLETION_SOURCE'"
    return 2
  } &
  for job in $(jobs -p | command sort)
  do
    wait "$job" || return $?
  done
}

cortex_try_profile() {
  if [ -z "${1-}" ] || [ ! -f "${1}" ]; then
    return 1
  fi
  echo "${1}"
}

#
# Detect profile file if not specified as environment variable
# (eg: PROFILE=~/.myprofile)
# The echo'ed path is guaranteed to be an existing file
# Otherwise, an empty string is returned
#
cortex_detect_profile() {
  if [ "${PROFILE-}" = '/dev/null' ]; then
    # the user has specifically requested NOT to have cortex touch their profile
    return
  fi

  if [ -n "${PROFILE}" ] && [ -f "${PROFILE}" ]; then
    echo "${PROFILE}"
    return
  fi

  local DETECTED_PROFILE
  DETECTED_PROFILE=''

  if [ -n "${BASH_VERSION-}" ]; then
    if [ -f "$HOME/.bashrc" ]; then
      DETECTED_PROFILE="$HOME/.bashrc"
    elif [ -f "$HOME/.bash_profile" ]; then
      DETECTED_PROFILE="$HOME/.bash_profile"
    fi
  elif [ -n "${ZSH_VERSION-}" ]; then
    DETECTED_PROFILE="$HOME/.zshrc"
  fi

  if [ -z "$DETECTED_PROFILE" ]; then
    for EACH_PROFILE in ".profile" ".bashrc" ".bash_profile" ".zshrc"
    do
      if DETECTED_PROFILE="$(cortex_try_profile "${HOME}/${EACH_PROFILE}")"; then
        break
      fi
    done
  fi

  if [ -n "$DETECTED_PROFILE" ]; then
    echo "$DETECTED_PROFILE"
  fi
}

cortex_do_install() {
  if [ -n "${CORTEX_DIR-}" ] && ! [ -d "${CORTEX_DIR}" ]; then
    if [ -e "${CORTEX_DIR}" ]; then
      echo >&2 "File \"${CORTEX_DIR}\" has the same name as installation directory."
      exit 1
    fi

    if [ "${CORTEX_DIR}" = "$(cortex_default_install_dir)" ]; then
      mkdir "${CORTEX_DIR}"
    else
      echo >&2 "You have \$CORTEX_DIR set to \"${CORTEX_DIR}\", but that directory does not exist. Check your profile files and environment."
      exit 1
    fi
  fi
  if [ -z "${METHOD}" ]; then
    # Autodetect install method
    if cortex_has git; then
      install_cortex_from_git
    elif cortex_has cortex_download; then
      install_cortex_as_script
    else
      echo >&2 'You need git, curl, or wget to install cortex'
      exit 1
    fi
  elif [ "${METHOD}" = 'git' ]; then
    if ! cortex_has git; then
      echo >&2 "You need git to install cortex"
      exit 1
    fi
    install_cortex_from_git
  elif [ "${METHOD}" = 'script' ]; then
    if ! cortex_has cortex_download; then
      echo >&2 "You need curl or wget to install cortex"
      exit 1
    fi
    install_cortex_as_script
  else
    echo >&2 "The environment variable \$METHOD is set to \"${METHOD}\", which is not recognized as a valid installation method."
    exit 1
  fi

  echo

  local CORTEX_PROFILE
  CORTEX_PROFILE="$(cortex_detect_profile)"
  local PROFILE_INSTALL_DIR
  PROFILE_INSTALL_DIR="$(cortex_install_dir | command sed "s:^$HOME:\$HOME:")"

  SOURCE_STR="\\nexport CORTEX_DIR=\"${PROFILE_INSTALL_DIR}\"\\n[ -s \"\$CORTEX_DIR/cortex.sh\" ] && \\. \"\$CORTEX_DIR/cortex.sh\"  # This loads cortex\\n"

  # shellcheck disable=SC2016
  COMPLETION_STR='[ -s "$CORTEX_DIR/bash_completion" ] && \. "$CORTEX_DIR/bash_completion"  # This loads cortex bash_completion\n'
  BASH_OR_ZSH=false

  if [ -z "${CORTEX_PROFILE-}" ] ; then
    local TRIED_PROFILE
    if [ -n "${PROFILE}" ]; then
      TRIED_PROFILE="${CORTEX_PROFILE} (as defined in \$PROFILE), "
    fi
    echo "=> Profile not found. Tried ${TRIED_PROFILE-}~/.bashrc, ~/.bash_profile, ~/.zshrc, and ~/.profile."
    echo "=> Create one of them and run this script again"
    echo "   OR"
    echo "=> Append the following lines to the correct file yourself:"
    command printf "${SOURCE_STR}"
    echo
  else
    if cortex_profile_is_bash_or_zsh "${CORTEX_PROFILE-}"; then
      BASH_OR_ZSH=true
    fi
    if ! command grep -qc '/cortex.sh' "$CORTEX_PROFILE"; then
      echo "=> Appending cortex source string to $CORTEX_PROFILE"
      command printf "${SOURCE_STR}" >> "$CORTEX_PROFILE"
    else
      echo "=> cortex source string already in ${CORTEX_PROFILE}"
    fi
    # shellcheck disable=SC2016
    if ${BASH_OR_ZSH} && ! command grep -qc '$CORTEX_DIR/bash_completion' "$CORTEX_PROFILE"; then
      echo "=> Appending bash_completion source string to $CORTEX_PROFILE"
      command printf "$COMPLETION_STR" >> "$CORTEX_PROFILE"
    else
      echo "=> bash_completion source string already in ${CORTEX_PROFILE}"
    fi
  fi
  if ${BASH_OR_ZSH} && [ -z "${CORTEX_PROFILE-}" ] ; then
    echo "=> Please also append the following lines to the if you are using bash/zsh shell:"
    command printf "${COMPLETION_STR}"
  fi

  # Source cortex
  # shellcheck source=/dev/null
  \. "$(cortex_install_dir)/cortex.sh"

  cortex_install_node

  cortex_reset

  echo "=> Close and reopen your terminal to start using cortex or run the following to use it now:"
  command printf "${SOURCE_STR}"
  if ${BASH_OR_ZSH} ; then
    command printf "${COMPLETION_STR}"
  fi
}

#
# Unsets the various functions defined
# during the execution of the install script
#
cortex_reset() {
  unset -f cortex_has cortex_install_dir cortex_latest_version cortex_profile_is_bash_or_zsh \
    cortex_source cortex_node_version cortex_download install_cortex_from_git cortex_install_node \
    install_cortex_as_script cortex_try_profile cortex_detect_profile \
    cortex_do_install cortex_reset cortex_default_install_dir
}

[ "_$CORTEX_ENV" = "_testing" ] || cortex_do_install

} # this ensures the entire script is downloaded #
