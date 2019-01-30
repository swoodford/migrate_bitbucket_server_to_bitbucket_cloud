#!/usr/bin/env bash

# This script will update many local machine git repo URLs to Bitbucket Cloud URLs

# Copyright 2019 Shawn Woodford
# https://github.com/swoodford

# TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION:
# YOU MUST AGREE TO ALL TERMS IN APACHE 2.0 LICENSE PROVIDED IN LICENSE.md FILE
# THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND
# YOU AGREE TO ACCEPT ALL LIABILITY IN USING THIS WORK AND ASSUME ANY AND ALL RISKS ASSOCIATED WITH RUNNING THIS WORK

# Assumptions:
# You are using Bitbucket Cloud
# The repo names remain identical from old to new
# You want to update the git remote URL for every git repo subfolder that uses the old git domain as the remote URL

# Steps for use:
# Set all required variables below
# Copy this script to the folder which contains all your git repo subfolders
# Run the script


# Setup variables

# Your Bitbucket Cloud account Team name
CLOUDTEAM="exampleteam"

# Domain of your old Bitbucket Server Git URL
OLDGITDOMAIN="git.mycompany.com"

# Optionally enable Debug Mode which provides more verbose output for troubleshooting
DEBUGMODE=false

# Don't modify the below variables

scriptdir=$(pwd)
# scriptdir=$(cd -P -- "$(dirname -- "$0")" && pwd -P)

NEWGITURL="git@bitbucket.org:$CLOUDTEAM/"

# Functions

# Pause
function pause(){
	read -n 1 -s -p "Press any key to continue..."
	echo
}

# Fail
function fail(){
	tput setaf 1; echo "Failure: $*" && tput sgr0
	exit 1
}

# Success
function success(){
	tput setaf 2; echo "$*" && tput sgr0
}

function warning(){
	tput setaf 1; echo "Warning: $*" && tput sgr0
}

success "Updating git URLs..."

directories=$(ls -d */ | cut -f1 -d'/')
total=$(echo "$directories" | wc -l | tr -d '\040\011\012\015')
start=1
for (( count=$start; count<=$total; count++ )); do
	directory=$(echo "$directories" | nl | grep -w [^0-9][[:space:]]$count | cut -f2)

	cd "$scriptdir/$directory"
	if [ ! $? -eq 0 ]; then
		fail "Unable to change directory to $scriptdir/$directory"
	fi
	remote=$(git remote -v 2>&1)
	if [ ! $? -eq 0 ]; then
		fail "$remote"
	fi

	if $DEBUGMODE; then
		echo "$remote"
		pause
	fi

	if echo "$remote" | egrep -q "$OLDGITDOMAIN"; then
		echo "Updating $directory"
		repo=$(basename $(git remote get-url origin) .git)
		if $DEBUGMODE; then
			echo "Updating git remote to $NEWGITURL$repo"
			pause
		fi
		update=$(git remote set-url origin $NEWGITURL$repo)
		remote=$(git remote -v)
		if $DEBUGMODE; then
			echo "$remote"
			pause
		fi
		if echo "$remote" | egrep -q 'bitbucket.org'; then
			success "Updated $directory!"
		else
			fail "$directory"
		fi
	fi
done

success "Completed!"
