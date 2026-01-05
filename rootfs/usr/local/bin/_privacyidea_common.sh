#!/bin/bash

execute_scripts() {
  local script_dir="$1"
  local script_names

  if [[ -d "$script_dir" ]] && compgen -G "${script_dir}/*.sh" > /dev/null; then
    script_names=("$script_dir"/*.sh)
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
