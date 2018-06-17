#!/bin/bash

### Setup constants ###
#######################

LOG=${LOG:-"/dev/tty6"}
BASE_URL=${BASE_URL:-"https://raw.githubusercontent.com/barskern/BASSAL/master/"}

# Setup logging so that commands will default to writing to the
# logfile, and only commands that use 'log_stdout' will write
# to the STDOUT
exec &3>1 1>>${LOG} 2>&1

# Setup locale and keyboard
TZ="Europe/Oslo"
LOCALE="nb_NO.utf-8"
EXTRA_LOCALES=("nb_NO" "en_US")
KB_LAYOUT="no"
KB_MODEL="pc104"
KB_VARIANT="winkeys"

# Partition layout device numbers 
EFI_DEV_NR=1
ROOT_DEV_NR=2
HOME_DEV_NR=3
SWAP_DEV_NR=128

# Partition sizes
# The "home" partition will use the remaining space of the disk
EFI_SIZE="512M"
ROOT_SIZE="32GB"
SWAP_SIZE="8G"

# Base installation that will be installed with "pacstrap"
INCLUDE_UCODE="$(lscpu | grep "Model name" | grep -i "intel")"
BASE_PKGS=("base" "base-devel")
[[ $INCLUDE_UCODE ]] && BASE_PKGS+=("intel-ucode")

### Setup functions ###
#######################

# Log message to the logfile
log() {
	echo "$1"
}

# Log message to the logfile and display it to the user
log_stdout() {
	echo "$1" | tee /dev/fd/3
}

# Display an error message with dialog
dialog_error() {
	local msg=$1
	dialog --colors --title "\Zb\Z1\Zr Error \Zn" --msgbox "$msg" 0 60
}

# Display a warning message with dialog and give the user the opportunity to cancel
dialog_warning() {
	local msg=$1
	dialog --colors \
		--defaultno \
		--title "\Zb\Z3\Zr WARNING!! " \
		--yesno "$msg" \
		0 60 \
	|| exit
}

# Display a message with dialog and give the user the opportunity to cancel
dialog_message() {
	local title=$1
	local msg=$2
	dialog --colors \
		--title "$title" \
		--msgbox "\n$msg" \
		10 60 \
	|| exit
}

# Get file from git repository and return (in the variable ${__}) 
# a file path to the downloaded file
get_file() {
	local name=$1
	new_name="$(mktemp)"
	([[ ! -f "$new_name" ]] || [[ ! -f "$name" ]]) && exit 1
	
	if [[ ! -f $name ]]; then
		curl -o "$new_name" "$BASE_URL$name"
	else 
		ln -sf "$(readlink -f "$name")" "$new_name"
	fi
	__="$new_name"
	return 0
}

# Function which loops over the items and calls the mapper-function on each 
# item and records the status of the mapping-command
map_with_status() {
	local title=$1
	local mapper=$2
	declare -a items=("${!3}")
	# Because installation of packages can fail, 
	# turn of termination of script on fail because
	# we can handle those failures
	set +e 
	items_status=()
	len=${#items[@]}
	n=30 # Must be a multiple of 2
	# Run mapper on each item and display status in a mixedgauge window
	for ((i=0; i<$len; i++)) do
		read item <<< "${items[$i]}" 
		ii=$((2*$i))
		items_status[$ii]="$item"
		items_status[$(($ii + 1))]="7"
		if [[ $ii < $n ]]; then
			s=0
		else 
			s=$(($ii - $n + 2))
		fi
		items_display="${items_status[@]:$s:$n}"
		dialog --title "$title" \
			--mixedgauge "" 0 60 \
			$((100 * $i / $len)) \
			${items_display[@]}
		$mapper "$item"
		status="$?"
		items_status[$(($ii + 1))]="$status"
	done
	items_display="${items_status[@]:$s:$n}"
	dialog --title "$title" \
		--mixedgauge "" 0 60 \
		100 \
		${items_display[@]}
	set +e
	sleep 0.5
}

# vi:syntax=sh
set -e

# Verify that "dialog" is installed
pacman --sync --noconfirm --needed dialog \
|| { echo "Error at start of script. Are you sure youre running this script as root?\
Are you sure you have an internet connection?"; exit 1; }

### Start the actual script with a welcome  ###
###############################################

dialog_message \
"Barskern's Automatic Setup Scripts for ArchLinux" \
"This script will download, install and configure my custom environment."

### Install packages from packages.csv ###
##########################################

install_pkg() {
	local pkgname=$1
	pacman --sync --quiet --noconfirm --needed --noprogressbar "$pkgname"
}


get_file "packages.csv"
pkgs_file=${__}

readarray pkgs <<< "$(cat "$pkgs_file" | cut -d ',' -f 1)"

#map_with_status "Installing packages" install_pkg pkgs[@]

### Setup user environment ###
##############################

setup_user() {
	local username=$1
	# Setup for asking for a password
	tmp_pass1=$(mktemp)
	tmp_pass2=$(mktemp)
	error=0
	error_msg="\Zb\Z1\Zr Error: Passwords not matching \Zn"
	prompt="Nothing will be displayed while you type"

	dialog_message "Setup account for $username" "Since $username does not already exist, the following prompts will set a password for this user and initialize the user with a home directory"

	# Creates a do-while loop which askes for passwords until two
	# equal passwords are entered
	while
		dialog \
			--no-cancel \
			--colors \
			--title "Enter password" \
			--passwordbox "$prompt" \
			0 60 \
			2> $tmp_pass1 \
		|| exit

		pass=$(cat "$tmp_pass1")

		dialog \
			--no-cancel \
			--title "Repeat your password" \
			--passwordbox "" \
			0 60 \
			2> $tmp_pass2 \
		|| exit

		pass2=$(cat "$tmp_pass2")
		
		# Only add error message to prompt if it is not already added
		if ([[ ! "$pass" == "$pass2" ]] && [[ $error == 0 ]]); then
			prompt="$prompt\n\n$error_msg"
			error=1
		fi	  

		[[ ! "$pass" == "$pass2" ]]	
	do :; done
	rm "$tmp_pass1" "$tmp_pass2"

	useradd --create-home --gid wheel --password "$pass" "$username"
}
# Ask for username
tmp_username=$(mktemp)
dialog --no-cancel \
	--title "Specify username" \
	--inputbox "\nThis can either be the username of an existing user or a brand new username." 10 60 2> $tmp_username \
|| exit

username=$(cat "$tmp_username")
rm "$tmp_username"

# Setup user if user does not already exist
[[ ! -z "$(cat /etc/passwd | cut -d ':' -f 1 | grep "$username")" ]] \
|| setup_user "$username"

# Download and run user configuration as newly created user
get_file "bassal_user.sh"
user_script=${__}
su --command "$user_script" --shell /bin/bash "$username"
