#!/bin/bash

### Setup constants ###
#######################

LOG=${LOG:-"log.txt"}
BASE_URL=${BASE_URL:-"https://raw.githubusercontent.com/barskern/BASSAL/master/"}

# Setup logging so that commands will default to writing to the
# logfile, and only commands that use 'log_stdout' will write
# to the STDOUT
exec 3>&1
exec 1>>${LOG}
exec 2>&1

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

# Variables for homesick initialization
HOMESICK_CASTLE="dotfiles"
GITHUB_USER="barskern"

# Kernel parameters
KERNEL_PARAMS=(rw quiet)

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
	dialog_message "\Zb\Z1\Zr Error " "$msg" 
}

# Display a warning message with dialog
dialog_warning() {
	local msg=$1
	dialog_message "\Zb\Z3\Zr WARNING!! " "$msg"
}

# Display a message with dialog
dialog_message() {
	local title=$1
	local msg=$2
	dialog --colors \
		--title "$title" \
		--msgbox "\n$msg" \
		10 60 \
		1>&3 \
	|| exit
}

# Get file from git repository and return (in the variable ${__}) 
# a file path to the downloaded file
get_file() {
	local name=$1
	new_name="$(mktemp)"
	([[ ! -f "$new_name" ]] && [[ ! -f "$name" ]]) && { display_error "Unable to find temporary files"; exit 1; }
	
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
	n=38 # Must be a multiple of 2

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
			--mixedgauge "" \
			30 60 \
			$((100 * $i / $len)) \
			${items_display[@]} \
			1>&3

		$mapper "$item"
		items_status[$(($ii + 1))]="$?"
	done

	items_display="${items_status[@]:$s:$n}"
	dialog --title "$title" \
		--mixedgauge "" \
		30 60 \
		100 \
		${items_display[@]} \
		1>&3

	set +e
	sleep 0.5
}

# vi:syntax=sh
set -e

# Verify that "dialog" is installed
pacman --sync --noconfirm --needed dialog \
|| { log_stdout "Error at start of script. Are you sure youre running this script as root?\
Are you sure you have an internet connection?"; exit 1; }

### Start the actual script with a welcome  ###
###############################################

dialog_message \
"Barskern's Automatic Setup Scripts for ArchLinux" \
"This script will download, install and configure my custom environment."

### Install packages from packages.csv ###
##########################################

install_pkgs() {
	install_pkg() {
		local pkgname=$1
		pacman --sync --quiet --noconfirm --needed --noprogressbar "$pkgname"
	}

	get_file "data/packages.csv"
	readarray pkgs <<< "$(cat "$__" | cut -d ',' -f 1)"
	rm "$__"

	map_with_status "Installing packages" install_pkg pkgs[@]
}
install_pkgs

### Configure systemd units ###
###############################

get_file "data/systemd-units/i3-session.service"
cat "${__}" >"/etc/systemd/user/i3.service"

get_file "data/systemd-units/i3-session.target"
cat "${__}" >"/etc/systemd/user/i3.target"

get_file "data/systemd-units/compton.service"
cat "${__}" >"/etc/systemd/user/compton.service"

# Download file which launches the X-server with systemd
get_file "data/i3-sd.desktop"
cat "${__}" >"/usr/share/xsessions/i3-sd.desktop"

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

	dialog_message \
		"Setup account for $username" \
		"Since $username does not already exist, the following prompts will set a password for this user and initialize the user with a home directory"

	# Creates a do-while loop which askes for passwords until two
	# equal passwords are entered
	while
		dialog \
			--no-cancel \
			--colors \
			--title "Enter password" \
			--passwordbox "$prompt" \
			0 60 \
			1>&3 \
			2> $tmp_pass1 \
		|| exit

		pass=$(cat "$tmp_pass1")

		dialog \
			--no-cancel \
			--title "Repeat your password" \
			--passwordbox "" \
			0 60 \
			1>&3 \
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

# Ask for hostname
dialog --title "Specify hostname" \
	--inputbox "" \
	8 60 \
	1>&3 \
	2>/etc/hostname \
|| exit

# Ask for username
tmp_username=$(mktemp)
dialog --title "Specify username" \
	--inputbox "\nThis can either be the username of an existing user or a brand new username." \
	10 60 \
	1>&3 \
	2> $tmp_username \
|| exit
username=$(cat "$tmp_username")
rm "$tmp_username"

# Setup user if user does not already exist
[[ ! -z "$(cat /etc/passwd | cut -d ':' -f 1 | grep "$username")" ]] \
|| setup_user "$username"

# Download and run user configuration as newly created user
get_file "dist/bassal_user.sh"
sudo --user="$username" "bash $__" 1>&3
rm "$__"

### Configure lightdm ###
#########################
# PS! Has to be done after user setup because lightdm-mini-greeter
# is installed from the AUR, hence cannot be installed as root

sed -i -e "s/^#\?greeter-session=.*$/greeter-session=lightdm-mini-greeter/" /etc/lightdm/lightdm.conf

sed -i -e "s/^user\s=.*$/user = $username/" /etc/lightdm/lightdm-mini-greeter.conf

sed -i -e "s/^window-color\s=.*$/window-color = \"#F1F1F1\"/" /etc/lightdm/lightdm-mini-greeter.conf

sed -i -e "s,^background-image\s=.*$,background-image = \"/usr/share/backgrounds/login-wall.png\"," /etc/lightdm/lightdm-mini-greeter.conf

dialog_message \
	"Lightdm background" \
	"Add an image to \"/usr/share/backgrounds/login-wall.png\" to use as a background for the lightdm-mini-greeter"

clear
