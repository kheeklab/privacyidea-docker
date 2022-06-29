#!/bin/bash

function execute_scripts {
	if [ -e "${1}" ] && [[ $(find "${1}" -maxdepth 1 -name "*.sh" -printf "%f\n") ]]
	then
		echo "[PrivacyIDEA] Executing scripts in ${1}:"

		for SCRIPT_NAME in $(find "${1}" -maxdepth 1 -name "*.sh" -printf "%f\n" | sort)
		do
			echo ""
			echo "[PrivacyIDEA] Executing ${SCRIPT_NAME}."

			source "${1}/${SCRIPT_NAME}"
		done

		echo ""
	fi
}
