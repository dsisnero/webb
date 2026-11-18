#!/usr/bin/env bash
# Resolve the installed cross-language parity skill.
#
# The scripts in this directory are thin forwarding wrappers. The parity
# implementation lives in the installed skill so that updating the skill also
# updates this repository's gates. Never copy the skill's Ruby helpers here.
#
# Override the location with PARITY_SKILL_DIR when the skill is installed
# somewhere other than the default path.

PARITY_SKILL_DEFAULT="${PARITY_SKILL_DEFAULT:-${HOME}/.agents/skills/crystal_forge/skills/cross-language-crystal-parity}"

resolve_parity_skill_dir() {
  local dir="${PARITY_SKILL_DIR:-${PARITY_SKILL_DEFAULT}}"
  if [[ ! -d "${dir}/scripts" ]]; then
    echo "cross-language parity skill not found at: ${dir}" >&2
    echo "Set PARITY_SKILL_DIR to the installed skill directory." >&2
    return 2
  fi
  printf '%s\n' "${dir}"
}

# run_parity_script <script-name> [args...]
run_parity_script() {
  local name="$1"
  shift
  local dir
  dir="$(resolve_parity_skill_dir)" || return 2
  exec "${dir}/scripts/${name}" "$@"
}
