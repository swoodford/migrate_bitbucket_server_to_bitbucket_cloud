#!/usr/bin/env bash

# Install Requirements

if [ -n "$(command -v yum)" ]; then
	sudo yum install -y curl git jq bc openssl
fi
if [ -n "$(command -v apt-get)" ]; then
	sudo apt-get install -y curl git jq bc openssl
fi

# Check Command
function check_command(){
	for command in "$@"
	do
	    type -P $command &>/dev/null || fail "Unable to install $command, please install it manually."
	done
}

# Check for required applications
check_command curl git jq bc openssl
