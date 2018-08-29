#!/usr/bin/env bash

# Migrate Atlassian Bitbucket Server to Bitbucket Cloud

# Copyright 2018 Shawn Woodford
# https://github.com/swoodford

# Requires curl, git, jq, bc openssl


# TERMS AND CONDITIONS FOR USE, REPRODUCTION, AND DISTRIBUTION:
# YOU MUST AGREE TO ALL TERMS IN APACHE 2.0 LICENSE PROVIDED IN LICENSE.md FILE
# THIS WORK IS PROVIDED ON AN "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND
# YOU AGREE TO ACCEPT ALL LIABILITY IN USING THIS WORK AND ASSUME ANY AND ALL RISKS ASSOCIATED WITH RUNNING THIS WORK


# Steps for use:

# Create Bitbucket Cloud Account and Setup Team
# Create OAuth Consumer in Bitbucket Cloud with Full Permisions to Team Account
# Create Admin or System Admin level user for migration on your Bitbucket Server
# Set all required variables below then run ./migrate.sh

# Migration process works in the following way:
# Get list of all Projects and Repos from Bitbucket Server
# Create new Project in Bitbucket Cloud, Create new Repo in Cloud, Backup each Project Repo and all branches locally using git
# Add new git remote cloud, push all branches to cloud, send email to git committers when each repo is migrated

# Migration can be done in one of three ways, see MIGRATION METHOD variables section below


# Setup variables

############################
# BITBUCKET SERVER VARIABLES
############################

# Protocol and Hostname or Protocol and Hostname and Port of your Bitbucket Server Frontend
SERVERHOSTNAME="https://git.example.com:8443"

# Bitbucket Server API URL - Hostname and Rest API path (this script has only been tested with API version 1.0)
SERVERAPIURL="$SERVERHOSTNAME/rest/api/1.0"

# Hostname or Hostname and Port of your Bitbucket Server Git Clone URL
SERVERGITCLONEURL="ssh://git@git.example.com:7999"

# Username and password for Bitbucket Server account with Admin or System Admin level permissions on your Bitbucket Server
SERVERAPIUSER="admin"
SERVERAPIPASS="password"

# Limit max number of Projects/Repos Bitbucket Server API will return
LIMIT="1000"


############################
# BITBUCKET CLOUD VARIABLES
############################

# Username and password for account with Team Admin level permissions on your Bitbucket Cloud account
CLOUDAPIUSER="username@example.com"
CLOUDAPIPASS="cloudpassword"

# Your Bitbucket Cloud account Team name
CLOUDAPITEAM="exampleteam"

# Bitbucket Cloud API URL - Protocol and Hostname and Rest API path (this script has only been tested with API version 2.0)
CLOUDAPIURL="https://api.bitbucket.org/2.0"
CLOUDGITCLONEURL="git@bitbucket.org"

# Bitbucket Cloud OAuth consumer credentials
# You must create an OAuth consumer with full cloud account permissions at this URL:
# https://bitbucket.org/account/user/YOURTEAMNAME/oauth-consumers/new
OAuthKey="key"
OAuthSecret="secret"
OAuthURL="https://bitbucket.org/site/oauth2/access_token"


############################
# MIGRATION VARIABLES
############################

# Optionally enable Debug Mode which provides more verbose output for troubleshooting
DEBUGMODE=false

# All repos with commits IN THIS YEAR OR LATER will be migrated (applies to migrateALL function only)
CUTOFFYEAR="2000"

# A local directory with plenty of free space to perform a git clone of all repos as a backup prior to migration to cloud
REPOBACKUPDIR="/root/bitbucket-backups"
if ! [ -d $REPOBACKUPDIR ]; then
	mkdir "$REPOBACKUPDIR"
fi

# A local directory where email templates will be generated and stored
EMAILDIR="/root/bitbucket-emails"
if ! [ -d $EMAILDIR ]; then
	mkdir "$EMAILDIR"
fi

# Optionally skip migrating any Git LFS repos that require manual conversion to Git LFS format
# Any repo that is over 2GB in size cannot be migrated to cloud without converting to Git LFS
# List repo slugs using vertical bar (|) as separator
LFSREPOS="example_LFS_repo_slug1|example_LFS_repo_slug2"

# Optionally skip migrating any repos that have already been migrated
# List repo slugs using vertical bar (|) as separator
MIGRATEDREPOS="example_repo_slug_to_skip1|example_repo_slug_to_skip2"

# Determines the directory where this script is running from, don't change this
SCRIPTDIR=$(cd -P -- "$(dirname -- "$0")" && pwd -P)


############################
# MIGRATION METHOD
############################

# Migration can be done in one of three ways:
# Using Function migrateALL, will migrate ALL Projects and ALL Repos found on Bitbucket Server
migrateALL=true

# OR using Function migratePhases which is a plain text file containing a list of
# Project Keys and Repo Slugs separated by a TAB in the text file set in variable PHASEFILE
# This was designed to use values pasted from a spreadsheet with one or more rows containing projects and repo slugs
migratePhases=false
PHASEFILE="phase1.txt"
# PHASENUMBER="1"

# OR using migrateMultiplePhases which will migrate multiple phases at a time by iterating over each phase file
migrateMultiplePhases=false
# Number of sequential phases to migrate, requires having PHASEFILES like "phase1.txt, phase2.txt, etc."
NumberOfPhases="1"


############################
# SEND EMAILS USING AWS SES
############################

# Optionally Send an Email to Git Committers using OpenSSL TLS Client and AWS SES with IAM Credentials
# when each repo has completed migration informing them of the migration and the new repo URL
SENDEMAILS=false

# Email address to use in the FROM field of emails, example: user@domain.com
EMAIL_FROM="user"
EMAIL_FROM_DOMAIN="domain.com"

# AWS SES IAM Credentials
# You must create an IAM SMTP User
# To send email through Amazon SES using SMTP, you must create SMTP credentials at this URL:
# https://console.aws.amazon.com/ses/home?region=us-east-1#smtp-settings:
AWS_SMTP_Username="smtpuser"
AWS_SMTP_Password="smtppass"
AWSSESHostname="email-smtp.us-east-1.amazonaws.com:587"


############################
# FUNCTIONS
############################

# Check Command
function check_command(){
	for command in "$@"
	do
	    type -P $command &>/dev/null || fail "Unable to find $command, please install it and run this script again."
	done
}

function pause(){
	read -p "Press any key to continue..."
	# echo pause
}

function fail(){
	tput setaf 1; echo "Failure: $*" && tput sgr0
	exit 1
}

function failwithoutexit(){
	tput setaf 1; echo "Failure: $*" && tput sgr0
}

function warning(){
	tput setaf 1; echo "Warning: $*" && tput sgr0
}

# Horizontal Rule
function HorizontalRule(){
	echo "============================================================"
}

function self_update(){
	cd "$( dirname "${BASH_SOURCE[0]}" )"
	if ! git pull | egrep -iq "Already up-to-date.|Already up to date."; then
		echo "Update found, please re-run this script."
		exit 0
	fi
}


# Needed if running on Bitbucket Server
function bitbucketServer(){
	# Verify running as root or with sudo
	if [ "$(id -u)" != "0" ]; then
		if $DEBUGMODE; then
			whoami
		fi
		fail "Please run this script as root."
	fi

	# Verify the repo backup directory exists
	if ! [ -d $REPOBACKUPDIR ]; then
		fail "Repo backup directory does not exist: $REPOBACKUPDIR"
	fi

	## If issues with SSH/git clone:
	## Use "ssh-add" to add the correct SSH key to the authentication agent
	## Then run "ssh-add -l", find the SHA256 hash and paste it below
	# SHA256hash="hash"
	# if ! ssh-add -l | grep -q "$SHA256hash"; then
	# 	eval "$(ssh-agent -s)" > /dev/null
	# 	ssh-add /root/.ssh/id_rsa
	# fi
}

# Git Checkout, Git Pull, Git Fetch on every branch in the repo
function backup(){
	echo "Begin Local Backup"
	for branch in `git branch -r | grep -v /HEAD | cut -d / -f2-`; do
		CHECKOUT=$(git checkout "$branch")
		if [ ! $? -eq 0 ]; then
			fail "$CHECKOUT"
		fi
		if echo "$CHECKOUT" | egrep -iq "fatal"; then
			fail "$CHECKOUT"
		fi
		PULL=$(git pull 2>&1)
		if echo "$PULL" | egrep -iq "unmerged"; then
			fail "$PULL"
		fi
		if echo "$PULL" | egrep -iq "configuration"; then
			warning "$PULL"
			warning "(Branch $branch may no longer exist in remote.)"
		fi
		echo "$PULL"
		YEAR=$(git log -1 --date=short --pretty=format:'%cd' | cut -d \- -f1)
	done

	git fetch origin
}

# Get the Bitbucket Cloud OAuth Token
function getToken(){
	TOKEN=$(curl -sX POST -u "$OAuthKey:$OAuthSecret" "$OAuthURL" -d grant_type=client_credentials)
	if [[ -z $TOKEN ]]; then
		TOKEN=$(curl -skX POST -u "$OAuthKey:$OAuthSecret" "$OAuthURL" -d grant_type=client_credentials)
	fi
	if [ ! $? -eq 0 ]; then
		fail "$TOKEN"
	else
		TOKEN=$(echo "$TOKEN" | jq '.access_token' | cut -d \" -f2)
		if $DEBUGMODE; then
			echo TOKEN: $TOKEN
		fi
	fi
}

# Creates Each Project in Bitbucket Cloud
function cloudProject(){
	echo "Begin cloudProject"
	# Check if Project already exists in Cloud
	CHECKPROJECT=$(curl -u $CLOUDAPIUSER:$CLOUDAPIPASS $CLOUDAPIURL/teams/$CLOUDAPITEAM/projects/$PROJECTKEY -sL -w "%{http_code}" -o /dev/null)

	# Test HTTP status code
	if [[ "$CHECKPROJECT" == "200" ]]; then
		echo "Project exists in Cloud:" $PROJECTKEY
	else
		# Get Project Details
		PROJECTDETAILS=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY)
		PROJECTNAME=$(echo $PROJECTDETAILS | jq '.name'| cut -d \" -f2)
		PROJECTDESCRIPTION=$(echo $PROJECTDETAILS | jq '.description'| cut -d \" -f2)
		if [[ "$PROJECTDESCRIPTION" == "null" ]]; then
			# failwithoutexit PROJECT DESCRIPTION IS NULL!
			# pause
			PROJECTDESCRIPTION=""
		fi

		if $DEBUGMODE; then
			echo PROJECTKEY $PROJECTKEY
			echo PROJECTNAME $PROJECTNAME
			echo PROJECTDESCRIPTION $PROJECTDESCRIPTION
			pause
		fi

		getToken
		# Create the Project in Cloud
		body=$(cat << EOF
{
    "name": "$PROJECTNAME",
    "key": "$PROJECTKEY",
    "description": "$PROJECTDESCRIPTION",
    "is_private": true
}
EOF
)
		curl -sH "Content-Type: application/json" \
		-H "Authorization: Bearer $TOKEN" \
		-X POST \
		-d "$body" \
		$CLOUDAPIURL/teams/$CLOUDAPITEAM/projects/ | jq .
	fi
}


# Creates Each Repo in Bitbucket Cloud
function cloudRepo(){
	echo "Begin cloudRepo"
	# Check if Repo exists in Cloud and create it if needed
	CHECKREPOURL=$CLOUDAPIURL/repositories/$CLOUDAPITEAM/$THISSLUG
	CHECKREPO=$(curl -u $CLOUDAPIUSER:$CLOUDAPIPASS $CHECKREPOURL -sL -w "%{http_code}" -o /dev/null)

	if $DEBUGMODE; then
		curl -su $CLOUDAPIUSER:$CLOUDAPIPASS $CHECKREPOURL | jq .
	fi

	# Test HTTP status code
	if [[ "$CHECKREPO" == "200" ]]; then
		echo "Repo exists in Cloud:" $THISSLUG
	else
		if [[ "$CHECKREPO" == "404" ]]; then
			echo "Creating repo:" $THISSLUG
			# Get Repo Details
			REPODETAILS=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY/repos/$THISSLUG)
			REPONAME=$(echo $REPODETAILS | jq '.name' | cut -d \" -f2)

			if $DEBUGMODE; then
				echo REPODETAILS:
				echo $REPODETAILS | jq .
				pause
			fi

			getToken
			# Create the Repo in Cloud
			body=$(cat << EOF
{
    "scm": "git",
    "project": {
        "key": "$PROJECTKEY"
    },
    "name": "$REPONAME",
    "is_private": true
}
EOF
)
			CREATEREPO=$(curl -sH "Content-Type: application/json" \
			-H "Authorization: Bearer $TOKEN" \
			-X POST \
			-d "$body" \
			$CLOUDAPIURL/repositories/$CLOUDAPITEAM/$THISSLUG)
			if echo "$CREATEREPO" | egrep -iq "invalid|error"; then
				fail echo "$CREATEREPO" | jq .
			fi
		else
			failwithoutexit "Error checking if repo exists in Cloud:"
			curl -Ssu $CLOUDAPIUSER:$CLOUDAPIPASS $CHECKREPOURL | jq .
		fi
		# Verify Repo was created in Cloud
		CHECKREPOURL=$CLOUDAPIURL/repositories/$CLOUDAPITEAM/$THISSLUG
		CHECKREPO=$(curl -u $CLOUDAPIUSER:$CLOUDAPIPASS $CHECKREPOURL -sL -w "%{http_code}" -o /dev/null)
		# Test HTTP status code
		if [[ "$CHECKREPO" == "200" ]]; then
			echo "Confirmed Repo Created in Cloud:" $THISSLUG
		else
			failwithoutexit "Error creating repo in Cloud:"
			curl -Ssu $CLOUDAPIUSER:$CLOUDAPIPASS $CHECKREPOURL | jq .
			fail
		fi
	fi
}

function cloudMigrate(){
	echo "Begin cloudMigrate"
	if ! git remote | grep -qw cloud; then
		git remote add cloud "$CLOUDGITCLONEURL":"$CLOUDAPITEAM"/"$THISSLUG".git
	fi
	PUSHALL=$(git push --all cloud 2>&1)
	if echo "$PUSHALL" | egrep -iq "rejected"; then
		fail "$PUSHALL"
	fi
	PUSHTAGS=$(git push --tags cloud 2>&1)
	if echo "$PUSHTAGS" | egrep -iq "rejected"; then
		fail "$PUSHTAGS"
	fi
	echo "$PUSHALL"
	echo "Completed cloudMigrate"
}

function migratePhases(){
	echo "Begin migratePhases"
	# Load repo list for this phase
	if ! [[ -z $PHASENUMBER ]]; then
		PHASE=$(cat phase$PHASENUMBER.txt)
	else
		PHASE=$(cat $PHASEFILE)
	fi
	if [ ! $? -eq 0 ]; then
		fail "$PHASE"
	fi
	# Count repos to migrate in this phase
	TOTALINPHASE=$(echo "$PHASE" | wc -l | tr -d '\040\011\012\015')
	echo
	tput setaf 2; HorizontalRule
	echo "Total Repos to Migrate in Phase $PHASENUMBER: $TOTALINPHASE"
	HorizontalRule && tput sgr0
	echo
	START=1
	for (( COUNT=$START; COUNT<=$TOTALINPHASE; COUNT++ )); do
		# Select each project
		if echo "$PHASEFILE" | egrep -iq "csv"; then
			if $DEBUGMODE; then
				fail "CSV File not supported."
			fi
			PROJECTKEY=$(echo "$PHASE" | nl | grep -w [^0-9][[:space:]]$COUNT | cut -f2 | cut -d \, -f1)
			REPO=$(echo "$PHASE" | nl | grep -w [^0-9][[:space:]]$COUNT | cut -f2 | cut -d \, -f2)
		else
			PROJECTKEY=$(echo "$PHASE" | nl | grep -w [^0-9][[:space:]]$COUNT | cut -f2)
			REPO=$(echo "$PHASE" | nl | grep -w [^0-9][[:space:]]$COUNT | cut -f3)
		fi
		# Get Project Details
		PROJECTDETAILS=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY)
		PROJECTNAME=$(echo $PROJECTDETAILS | jq '.name'| cut -d \" -f2)
		echo
		HorizontalRule
		echo "Key:"; tput setaf 2; echo "$PROJECTKEY"; tput sgr0
		echo "Name:"; tput setaf 2; echo "$PROJECTNAME"; tput sgr0
		echo "Repo:"; tput setaf 2; echo "$REPO"; tput sgr0
		HorizontalRule
		echo
		SLUG="$REPO"
		THISSLUG="$SLUG"

		# Do not migrate LFS repos >2GB!!!
		if ! echo "$THISSLUG" | egrep -iq "$LFSREPOS"; then
			# If the slug path exists then run the backup function
			if [ -d $REPOBACKUPDIR/$PROJECTKEY/$SLUG ]; then
				if $DEBUGMODE; then
					echo "Path exists: $REPOBACKUPDIR/$PROJECTKEY/$SLUG"
					pause
				fi
				cd $REPOBACKUPDIR/$PROJECTKEY/$SLUG
				backup
				if [ "$YEAR" -gt "$CUTOFFYEAR" -o "$YEAR" -eq "$CUTOFFYEAR" ]; then
					echo "Repo year: $YEAR"
					cloudProject
					cloudRepo
					cloudMigrate
					if $SENDEMAILS; then
						generateEmail
						TO=$(git log --pretty="%ae")
						sendEmail
					fi
				else
					echo "Repo year $YEAR is older than cutoff year $CUTOFFYEAR.  Not migrating $THISSLUG to cloud!"
				fi
			fi
			# If the slug path doesn't exist then clone the repo and run the backup function
			if ! [ -d $REPOBACKUPDIR/$PROJECTKEY/$SLUG ]; then
				if $DEBUGMODE; then
					echo "Path doesn't exist: $REPOBACKUPDIR/$PROJECTKEY/$SLUG"
					pause
				fi
				CLONEURL="$SERVERGITCLONEURL/$PROJECTKEY/$SLUG.git"
				# # List repo clone URL within project
				# CLONEURL=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY/repos?limit=$LIMIT --tlsv1 | jq '.values | .[] | .links | .clone | .[] | .href' | cut -d \" -f2 | grep ssh)
				if $DEBUGMODE; then
					echo "Cloning the repo from:"
					echo "$CLONEURL"
				fi
				cd "$REPOBACKUPDIR"
				if ! [ -d "$PROJECTKEY" ]; then
					mkdir "$PROJECTKEY"
				fi
				cd "$PROJECTKEY"
				CLONE=$(git clone "$CLONEURL" 2>&1)
				if [ ! $? -eq 0 ]; then
					fail "$CLONE"
				fi
				if echo "$CLONE" | egrep -iq "fatal|not|denied"; then
					fail "$CLONE"
				fi
				cd "$SLUG"
				backup
				if [ "$YEAR" -gt "$CUTOFFYEAR" -o "$YEAR" -eq "$CUTOFFYEAR" ]; then
					echo "Repo year: $YEAR"
					cloudProject
					cloudRepo
					cloudMigrate
					if $SENDEMAILS; then
						generateEmail
						TO=$(git log --pretty="%ae")
						sendEmail
					fi
				else
					echo "Repo year $YEAR is older than cutoff year $CUTOFFYEAR.  Not migrating $THISSLUG to cloud!"
				fi
			fi
		else
			warning "LFS Repo $THISSLUG will not be migrated!"
		fi
	done
}

function migrateALL(){
	echo "Begin migrateALL"
	# List all projects
	PROJECTS=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects?limit=$LIMIT --tlsv1 | jq '.values | .[] | .key' | cut -d \" -f2)
	if [[ -z $PROJECTS ]]; then
		fail "Unable to list Bitbucket Projects."
	fi

	if $DEBUGMODE; then
		echo "$PROJECTS"
		pause
	fi

	# Count projects
	TOTALPROJECTS=$(echo "$PROJECTS" | wc -l | tr -d '\040\011\012\015')

	if $DEBUGMODE; then
		echo "Total Projects: $TOTALPROJECTS"
		pause
	fi

	TOTALSLUGS=0
	START=1
	for (( COUNT=$START; COUNT<=$TOTALPROJECTS; COUNT++ )); do
		# Select each project
		PROJECTKEY=$(echo "$PROJECTS" | nl | grep -w [^0-9][[:space:]]$COUNT | cut -f2)
		if [[ -z $PROJECTKEY ]]; then
			fail "Unable to select Bitbucket Project."
		fi
		HorizontalRule
		echo "$COUNT Project: $PROJECTKEY"

		# Get slugs (individual repos within project)
		SLUG=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY/repos?limit=$LIMIT --tlsv1 | jq '.values | .[] | .slug' | cut -d \" -f2)
		if [[ -z $SLUG ]]; then
			echo "Unable to get Bitbucket project slugs for $PROJECTKEY."
		fi

		# Count number of repos in the project
		NUMSLUGS=$(echo "$SLUG" | wc -l | tr -d '\040\011\012\015')
		if $DEBUGMODE; then
			echo "NumSlugs:" "$NUMSLUGS"
		fi

		TOTALSLUGS=$(($TOTALSLUGS + $NUMSLUGS))

		# Case: One Repo in the Project
		if [ "$NUMSLUGS" -eq "1" ]; then
			echo "Repo:" "$SLUG"
			THISSLUG="$SLUG"

			# Do not migrate repos that are already migrated and using cloud!!!
			if ! echo "$THISSLUG" | egrep -iq "$MIGRATEDREPOS"; then

				# Do not migrate LFS repos >2GB!!!
				if ! echo "$THISSLUG" | egrep -iq "$LFSREPOS"; then

					# If the slug path exists then run the backup function
					if [ -d $REPOBACKUPDIR/$PROJECTKEY/$SLUG ]; then
						if $DEBUGMODE; then
							echo "Path exists:" "$REPOBACKUPDIR/$PROJECTKEY/$SLUG"
							pause
						fi
						cd $REPOBACKUPDIR/$PROJECTKEY/$SLUG
						backup
						if [ "$YEAR" -gt "$CUTOFFYEAR" -o "$YEAR" -eq "$CUTOFFYEAR" ]; then
							getToken
							cloudProject
							cloudRepo
							cloudMigrate
						else
							echo "Repo year $YEAR is older than cutoff year $CUTOFFYEAR.  Not migrating $THISSLUG to cloud!"
						fi
					fi

					# If the slug path doesn't exist then clone the repo and run the backup function
					if ! [ -d $REPOBACKUPDIR/$PROJECTKEY/$SLUG ]; then
						if $DEBUGMODE; then
							echo "Path doesn't exist:" "$REPOBACKUPDIR/$PROJECTKEY/$SLUG"
							pause
						fi

						# List repo clone URL within project
						CLONEURL=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY/repos?limit=$LIMIT --tlsv1 | jq '.values | .[] | .links | .clone | .[] | .href' | cut -d \" -f2 | grep ssh)
						if $DEBUGMODE; then
							echo "Cloning the repo from:"
							echo "$CLONEURL"
						fi
						cd $REPOBACKUPDIR
						if ! [ -d $PROJECTKEY ]; then
							mkdir $PROJECTKEY
						fi
						cd $PROJECTKEY
						CLONE=$(git clone "$CLONEURL" 2>&1)
						if [ ! $? -eq 0 ]; then
							fail "$CLONE"
						fi
						if echo "$CLONE" | egrep -iq "fatal|not|denied"; then
							fail "$CLONE"
						fi
						cd $SLUG
						backup
						if [ "$YEAR" -gt "$CUTOFFYEAR" -o "$YEAR" -eq "$CUTOFFYEAR" ]; then
							getToken
							cloudProject
							cloudRepo
							cloudMigrate
						else
							echo "Repo year $YEAR is older than cutoff year $CUTOFFYEAR.  Not migrating $THISSLUG to cloud!"
						fi
					fi
				else
					warning "LFS Repo $THISSLUG will not be migrated!"
				fi
			else
				warning "Repo $THISSLUG has already been migrated to cloud!"
			fi
		fi

		# Case: Multiple Repos in the Project
		if [ "$NUMSLUGS" -gt "1" ]; then
			if $DEBUGMODE; then
				echo "Number of slugs greater than 1!"
				pause
			fi

			# Backup one slug at a time
			STARTSLUG=1
			for (( SLUGCOUNT=$STARTSLUG; SLUGCOUNT<=$NUMSLUGS; SLUGCOUNT++ )); do
				THISSLUG=$(echo "$SLUG" | nl | grep -w [^0-9][[:space:]]$SLUGCOUNT | cut -f2)

				# Do not migrate repos that are already migrated and using cloud!!!
				if ! echo "$THISSLUG" | egrep -iq "$MIGRATEDREPOS"; then

					# Do not migrate LFS repos >2GB!!!
					if ! echo "$THISSLUG" | egrep -iq "$LFSREPOS"; then

						# If the slug path does exist then run the backup function
						if [ -d $REPOBACKUPDIR/$PROJECTKEY/$THISSLUG ]; then
							if $DEBUGMODE; then
								echo "Path exists:" "$REPOBACKUPDIR/$PROJECTKEY/$THISSLUG"
								pause
							fi
							echo "Repo:" "$THISSLUG"
							cd $REPOBACKUPDIR/$PROJECTKEY/$THISSLUG
							backup
							if [ "$YEAR" -gt "$CUTOFFYEAR" -o "$YEAR" -eq "$CUTOFFYEAR" ]; then
								getToken
								cloudProject
								cloudRepo
								cloudMigrate
							else
								echo "Repo year $YEAR is older than cutoff year $CUTOFFYEAR.  Not migrating $THISSLUG to cloud!"
							fi
						fi

						# If the slug path doesn't exist then clone the repo and run the backup function
						if ! [ -d $REPOBACKUPDIR/$PROJECTKEY/$THISSLUG ]; then
							if $DEBUGMODE; then
								echo "Path doesn't exist:" "$REPOBACKUPDIR/$PROJECTKEY/$THISSLUG"
								pause
							fi

							cd $REPOBACKUPDIR
							if ! [ -d $PROJECTKEY ]; then
								mkdir $PROJECTKEY
							fi
							cd $PROJECTKEY

							# This isn't needed since we already know the slug and can generate the clone url

							# # List repo clone URLs within project
							# CLONEURLS=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY/repos?limit=$LIMIT --tlsv1 | jq '.values | .[] | .links | .clone | .[] | .href' | cut -d \" -f2 | grep ssh)

							# STARTCLONEURL=1
							# for (( CLONEURLCOUNT=$STARTCLONEURL; CLONEURLCOUNT<=$NUMSLUGS; CLONEURLCOUNT++ )); do
							# 	THISCLONEURL=$(echo "$CLONEURLS" | nl | grep -w [^0-9][[:space:]]$CLONEURLCOUNT | cut -f2)

							# 	if $DEBUGMODE; then
							# 		echo
							# 		echo "CLONEURLS:"
							# 		echo "$CLONEURLS"
							# 		echo
							# 		echo "CLONEURLCOUNT:"
							# 		echo "$CLONEURLCOUNT"
							# 		echo
							# 		echo "Cloning the repo from:"
							# 		echo "$THISCLONEURL"
							# 	fi

							# 	cd $REPOBACKUPDIR/$PROJECTKEY
							THISCLONEURL=$(curl -sku $SERVERAPIUSER:$SERVERAPIPASS $SERVERAPIURL/projects/$PROJECTKEY/repos/$THISSLUG --tlsv1 | jq '.links | .clone | .[] | .href' | cut -d \" -f2 | grep ssh)
							CLONE=$(git clone "$THISCLONEURL" 2>&1)
							if [ ! $? -eq 0 ]; then
								fail "$CLONE"
							fi
							if echo "$CLONE" | egrep -iq "fatal|not|denied"; then
								fail "$CLONE"
							fi
							cd $THISSLUG
							if [ ! $? -eq 0 ]; then
								fail "$THISSLUG"
							fi
							backup
							if [ "$YEAR" -gt "$CUTOFFYEAR" -o "$YEAR" -eq "$CUTOFFYEAR" ]; then
								getToken
								cloudProject
								cloudRepo
								cloudMigrate
							else
								echo "Repo year $YEAR is older than cutoff year $CUTOFFYEAR.  Not migrating $THISSLUG to cloud!"
							fi
							# done
						fi
					else
						warning "LFS Repo $THISSLUG will not be migrated!"
					fi
				else
					warning "Repo $THISSLUG has already been migrated to cloud!"
				fi
			done
		fi

		# Calculate and display completion percentage
		PERCENT=$(echo "scale=2; 100/$TOTALPROJECTS" | bc)
		PERCENTCOMPLETED=$(echo "scale=2; $PERCENT*$COUNT" | bc)
		PERCENTCOMPLETED=$(echo "($PERCENTCOMPLETED+0.5)/1" | bc)
		echo $PERCENTCOMPLETED% of Projects Completed.
	done

	echo "Total Repos on Server: $TOTALSLUGS"
	echo "Total Projects on Server: $TOTALPROJECTS"

	# # Not migrating every project/repo so this check is no longer useful
	# VERIFY=$(curl -su $CLOUDAPIUSER:$CLOUDAPIPASS "$CLOUDAPIURL/teams/$CLOUDAPITEAM/projects/" | jq '.size')
	# if [[ "$TOTALPROJECTS" == "$VERIFY" ]]; then
	# 	echo
	# 	HorizontalRule
	# 	echo "Bitbucket Migration has completed."
	# 	HorizontalRule
	# else
	# 	echo
	# 	HorizontalRule
	# 	echo "Unable to verify all projects were migrated."
	# 	HorizontalRule
	# fi
}

function generateEmail(){
	HorizontalRule
	echo "Generating Email Template"
	HorizontalRule
(
cat << EOP
Hello, this repository is being migrated to Bitbucket Cloud:

Project: $PROJECTNAME
Repository: $REPO

Please do not push any more commits to the current repo as you will no longer have write permission during the migration.

Old URL:
https://$SERVERHOSTNAME/projects/$PROJECTKEY/repos/$REPO/browse

New URL:
https://bitbucket.org/$CLOUDAPITEAM/$THISSLUG

You will need to update your local git repo using the following command:
git remote set-url origin $CLOUDGITCLONEURL:$CLOUDAPITEAM/$THISSLUG.git

Or if you use Sourcetree, update the repo URL to:
$CLOUDGITCLONEURL:$CLOUDAPITEAM/$THISSLUG.git
EOP
) > $EMAILDIR/$REPO
}

function sendEmail(){

	# Clean up To list - convert to lower case, sort, filter unique, remove former employees, filter out non-company email addresses
	TO=$(echo "$TO" | tr '[:upper:]' '[:lower:]' | sort | uniq | egrep -vw 'formeremployee1|formeremployee2' | sed -n '/'"$EMAIL_FROM_DOMAIN"'$/p')

	if [[ -z $TO ]]; then
		echo "No users to email."
		return 1
	fi

	echo "Pausing before sending email to:"
	echo "$TO"
	read -r -p "Continue? (y/n) " CONTINUE
	HorizontalRule

	FROM="$EMAIL_FROM@$EMAIL_FROM_DOMAIN"
	SUBJECT="$PROJECTNAME - $REPO Bitbucket Cloud Migration"
	MESSAGE=$(cat $EMAILDIR/$REPO)

if [[ $CONTINUE =~ ^([yY][eE][sS]|[yY])$ ]]; then
for to in $TO
do
HorizontalRule
echo "Sending mail to $to"
HorizontalRule
(
cat << EOP
EHLO $EMAIL_FROM_DOMAIN
AUTH LOGIN
$AWS_SMTP_Username
$AWS_SMTP_Password
MAIL FROM: $FROM
RCPT TO: $to
DATA
From: $FROM
To: $to
Subject: $SUBJECT

$MESSAGE
.
QUIT

EOP
) > $EMAILDIR/email
openssl s_client -crlf -quiet -starttls smtp -connect $AWSSESHostname < $EMAILDIR/email
done
fi
}

# Update the backup script
self_update


# Check for required applications
check_command curl git jq bc openssl

# Log the Date/Time
echo
echo
HorizontalRule
HorizontalRule
tput setaf 2; HorizontalRule
echo "Beginning Bitbucket Migration"
date +%m-%d-%Y" "%H:%M:%S
HorizontalRule && tput sgr0
HorizontalRule
HorizontalRule
echo
echo

bitbucketServer

# # Migrate Phases
if $migrateMultiplePhases; then
	for PHASENUMBER in {$NumberOfPhases..1}; do
		cd "$SCRIPTDIR"
		migratePhases
	done
fi

# PHASEFILE="phase1.txt"
if $migratePhases; then
	migratePhases
fi

# Migrate all
migrateALL


# Log the Date/Time again when completed
echo
echo
HorizontalRule
HorizontalRule
tput setaf 2; HorizontalRule
echo "Completed Bitbucket Migration"
date +%m-%d-%Y" "%H:%M:%S
HorizontalRule && tput sgr0
HorizontalRule
HorizontalRule
echo
echo
