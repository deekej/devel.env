#!/usr/bin/env bash

# Setup script for Dee'Kej's personal devel & admin environment.
# --------------------------------------------------------------

export LC_ALL=C

# Enable aliases inside the script:
shopt -s expand_aliases

# -----------------------------------------------------------------------------

PROG="$(basename "${0}")"

DISTRO="$(lsb_release --id --short| tr '[:upper:]' '[:lower:]')"
#DISTRO_VER="$(lsb_release --release --short | cut -d '.' -f 1)"

PACKAGES=(
    coreutils-common      # terminal color support
    colordiff             # color support for diff
  )

# ------------------

USER=''
HOME=''
CONFIG=''
PROFILE_D=''

# ------------------

OPT_INIT=false

OPT_MINIMAL=false
OPT_DEFAULT=false
OPT_FULL=false

OPT_GIT=false
OPT_GIT_PROMPT=false

OPT_VIM=false
OPT_SSH=false

OPT_ZSH=false
OPT_BASH=false

OPT_ROOT=false
OPT_SYSTEM_WIDE=false

OPT_DRY_RUN=false
OPT_UPDATE=false

SUDO_USED=false

# -----------------------------------------------------------------------------

function display_usage()
{
  printf "Usage: %s [--default | --full | --minimal] [--user name] option [options]

Options:
  -h, --help          display this info and exit

  -I, --init          basic initialization (e.g. packages installation)

  -b, --bash          prepare the Bash configuration
  -z, --zsh           prepare the ZSH configuration

  -s, --ssh           prepare the SSH configuration
  -v, --vim           prepare the VIM configuration

  -g, --git           prepare the Git configuration
  -p, --git-prompt    prepare the git-prompt configuration

  -u, --user name     override username to specific one
  -H, --home path     override user's default /home/user path

  -X, --dry-run       do not change anything, only display what would change
  -U, --update        update the current environment with latest changes

Mutually exclusive group:
  -D, --default       prepare the ZSH, GIT, VIM & SSH configuration
  -m, --minimal       prepare only the Bash & SSH configuration
  -f, --full          prepare everything

Elevated rights needed:
  -r, --root          set the devel environment for 'root' user as well
  -W, --system-wide   apply the configuration system wide (e.g. profile.d/)

NOTE: It is mandatory to supply at least one option.\n" "${PROG}"
}

# ------------------

# Display error message, usage and exit:
function args_error()
{
  echo -e "${PROG}: error: ${1}\n" >&2;
  display_usage >&2;
  exit ${2:-1};
}

# -----------------------------------------------------------------------------

# Evaluate shvar-style booleans - taken from Fedora System V initscripts:
is_true() {
    case "${1}" in
      1)                    return 0;;    # 1
      [tT])                 return 0;;    # T
      [yY])                 return 0;;    # Y
      [oO][nN])             return 0;;    # on
      [yY][eE][sS])         return 0;;    # yes
      [tT][rR][uU][eE])     return 0;;    # true
      *)                    return 1;;
    esac
}

is_false() {
    case "${1}" in
      0)                    return 0;;    # 0
      [fF])                 return 0;;    # F
      [nN])                 return 0;;    # N
      [nN][oO])             return 0;;    # no
      [oO][fF][fF])         return 0;;    # off
      [fF][aA][lL][sS][eE]) return 0;;    # false
      *)                    return 1;;
    esac
}

# -----------------------------------------------------------------------------

function process_args()
{
  PARSED_ARGS=$(getopt --name "${PROG}" \
                       --alternative \
                       --options IDmfbzvsgprWXUuHh \
                       --long init \
                       --long default \
                       --long minimal \
                       --long full \
                       --long bash \
                       --long zsh \
                       --long vim \
                       --long ssh \
                       --long git \
                       --long git-prompt \
                       --long root \
                       --long system-wide \
                       --long dry-run \
                       --long update \
                       --long user: \
                       --long home: \
                       --long help \
                       -- "${@}")

  case "${?}" in
    0) true;;                                     # Success, continue...
    1) echo "" >&2; display_usage >&2; exit 1;;   # Wrong parameter used.
    *) args_error "getopt failed\nTerminating..." 127;;
  esac

  local arg_used=false
  local mxg=0

  # We use "$@" instead of $* to preserve argument-boundary information:
  eval set -- "${PARSED_ARGS}"

  while true; do
    case "${1}" in
      -I | --init)        arg_used=true; OPT_INIT=true;               shift   ;;

      -D | --default)     arg_used=true; OPT_DEFAULT=true; ((mxg++)); shift   ;;
      -m | --minimal)     arg_used=true; OPT_MINIMAL=true; ((mxg++)); shift   ;;
      -f | --full)        arg_used=true; OPT_FULL=true;    ((mxg++)); shift   ;;

      -b | --bash)        arg_used=true; OPT_BASH=true;               shift   ;;
      -z | --zsh)         arg_used=true; OPT_ZSH=true;                shift   ;;

      -v | --vim)         arg_used=true; OPT_VIM=true;                shift   ;;
      -s | --ssh)         arg_used=true; OPT_SSH=true;                shift   ;;

      -g | --git)         arg_used=true; OPT_GIT=true;                shift   ;;
      -p | --git-prompt)  arg_used=true; OPT_GIT_PROMPT=true;         shift   ;;

      -r | --root)        arg_used=true; OPT_ROOT=true;               shift   ;;
      -W | --system-wide) arg_used=true; OPT_SYSTEM_WIDE=true;        shift   ;;

      -X | --dry-run)     arg_used=true; OPT_DRY_RUN=true;            shift   ;;
      -U | --update)      arg_used=true; OPT_UPDATE=true;             shift   ;;

      # These are separate options which still require other options:
      -u | --user)        USER="${2}";                                shift 2 ;;
      -H | --home)        HOME="${2}";                                shift 2 ;;

      -h | --help)        display_usage;                               exit 0 ;;
      --)                 shift; break;;    # End of processed arguments.

      # The below code should never be reached, unless getopt failed somehow:
      *)   args_error "Unprocessed option by getopt: ${1}\nTerminating..." 127;;
    esac
  done

  # Any not processed options?
  if [[ -n "${*}" ]]; then
    args_error "unrecognized option '${*}'" 1;
  fi

  # At least one option has to be used (ignoring --user option):
  if is_false "${arg_used}"; then
    args_error "no option specified" 1;
  fi

  # Mutually exclusive options used?
  if [[ ${mxg} -gt 1 ]]; then
    args_error "'--default', '--minimal' and '--full' options are mutually exclusive" 1;
  fi

  # Do we have elevated rights?
  if [[ ${EUID} == 0 ]]; then
    SUDO_USED=true
  fi

  if is_true "${OPT_ROOT}" || is_true "${OPT_SYSTEM_WIDE}"; then
    if is_false "${SUDO_USED}"; then
      args_error "'--root' and '--system-wide' options require elevated rights" 1;
    fi
  fi

  # Prepare the necessary variables:
  USER="${USER:-${USERNAME}}"
  HOME="${HOME:-/home/${USERNAME}}"
  CONFIG="${HOME}/.config/devenv"

  if is_true "$OPT_SYSTEM_WIDE"; then
    PROFILE_D='/etc/profile.d/'
  else
    PROFILE_D="${HOME}/.config/profile.d/"
  fi
}

# -----------------------------------------------------------------------------

# 1st argument: git repository URL
# 2nd argument: path where the repository should be cloned
# 3rd argument: optional path for separate git repository
#
# TODO: use builtin associative array for obtaining repository links
# TODO: use 'master' as default branch
# TODO: use requested repo branch from CONFIG file
# TODO: Add dry-run wrapper
function git_clone()
{
  local url="${1}"
  local path="${2}"
  local git_path="${3}"

  if [[ -z "${url}" || -z "${path}" ]]; then
    echo "${PROG}: warning: skipping cloning of repository" >&2
    echo "${PROG}: warning: URL or path not specified..." >&2
    return
  fi

  if [[ -e "${path}/.git" ]]; then
    echo "${PROG}: warning: '${path}/.git/' already exists" >&2
    echo "${PROG}: warning: skipping cloning of '${url}' repository" >&2
    return
  fi

  if [[ -d "${path}" && -s "${path}" ]]; then
    cd "${path}"

    git init ${git_path:+--separate-git-dir} ${git_path:+${git_path}}
    git remote add origin "${url}"

    git fetch --all
    git reset --hard origin/master
    git branch --set-upstream-to=origin/master

    git submodule init
    git pull origin master --recurse-submodules

    cd -
  else
    mkdir -p "${path}"

    git clone --recurse-submodules "${url}" "${path}" \
              ${git_path:+--separate-git-dir} ${git_path:+${git_path}}
  fi
}

# ------------------

# Basic packages:
# * bash + bash completion
# * git + git completion
#
# Additional packages - installed as a dependecies for each option:
# * bash + bash completion + devscripts-checkbashisms
# * zsh +
# * gitflow + git-email + git2cl

function init_setup()
{
  if is_false "${SUDO_USED}"; then
    return
  elif is_false "${OPT_INIT}" && is_true "${INIT_SETUP_DONE}"; then
    return
  fi

  local pacman

  # Determine which package manager to use:
  if command -v dnf; then
    pacman=dnf
  elif command -v yum; then
    pacman=yum
  else
    echo "${PROG}: warning: '${DISTRO}' distribution is not supported" >&2
    echo "${PROG}: warning: skipping initialization step..." >&2
    return
  fi

  # Install the requested packages:
  $pacman install --refresh --assumeyes "${PACKAGES[@]}"

  OPT_INIT=done
}

# -----------------------------------------------------------------------------

# Process arguments
process_args "${@}"

# Load configuration file if it exists:
if [ -f "${CONFIG}" ]; then
  source "${CONFIG}"
fi
