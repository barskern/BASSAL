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
KB_MODEL="acer_laptop"
KB_VARIANT="winkeys"
KB_OPTIONS="caps:escape"

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

### Setup boot-loader ###
#########################

setup_bootloader() {
	# Get PARTUUID of the root partition
	dev_path="$(lsblk --noheadings --path --raw --output MOUNTPOINT,NAME | grep "^/\s" | cut -d ' ' -f 2)"
	root_uuid="$(blkid | grep "$dev_path" | sed 's/.*PARTUUID="//' | tr -d \")"

	bootctl install --path="/boot"

loader_conf="\
default	arch
timeout	0
editor	no
"

	[[ $INCLUDE_UCODE ]] && initrd_ucode="\ninitrd\t/intel-ucode.img"

arch_conf="\
title	Arch Linux
linux	/vmlinuz-linux
initrd	/initramfs-linux.img$initrd_ucode
options	root=PARTUUID=$root_uuid ${KERNEL_PARAMS[@]}
"

	echo -e "$loader_conf" > "/boot/loader/loader.conf"
	echo -e "$arch_conf" > "/boot/loader/entries/arch.conf"

	bootctl update
}
setup_bootloader

### Run main installer ###
##########################

get_file "dist/bassal_main.sh"
bash "$__" 1>&3
rm "$__"
