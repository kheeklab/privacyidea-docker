#!/bin/bash

execute_scripts() {
  local script_dir="$1"
  local script_names=()

  if [[ ! -d "$script_dir" ]]; then
    return 0
  fi

  shopt -s nullglob
  script_names=("$script_dir"/*.sh)
  shopt -u nullglob

  if (( ${#script_names[@]} )); then
    echo "[PrivacyIDEA] Executing scripts in $script_dir:"

    for script_path in "${script_names[@]}"; do
      local script_name=$(basename "$script_path")
      echo ""
      echo "[PrivacyIDEA] Executing $script_name."
      echo ""
      source "$script_path" || { echo "[ERROR]: Failed to execute $script_name."; return 1; }
    done

    echo ""
  fi
}
