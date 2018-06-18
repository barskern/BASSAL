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
	([[ ! -f "$new_name" ]] && [[ ! -f "$name" ]]) && exit 1
	
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

# Check that dialog is installed
pacman --sync --noconfirm --needed dialog \
|| { log_stdout "Error at start of script. Are you sure youre running this script as root? Are you sure you have an internet connection?"; exit 1; }

# Check that the current system supports UEFI
[[ ! -d "/sys/firmware/efi" ]] \
&& { log_stdout "You have to be booted with EFI to use this script. Install a minimal ArchLinux installation and run \"bassal.sh\" to use my custom configurations."; exit 1; }

### Welcome message ###
#######################

dialog \
	--colors \
	--defaultno \
	--title "Welcome to the pure setup of BASSEL" \
	--yesno "
	This pure setup will do \Z3EVERYTHING\Zn:
	
	- Partitioning
	- Mounting
	- Installing
	- Configuring
	
	If you're not looking for the full package, use \"bassal.sh\" instead which only installs and configures custom settings" \
	0 60 \
	1>&3 \
|| exit

### Actions done pre-chroot ###
###############################

dialog_warning "This script will erase \Zb\Z1\Zr ALL \Zn data on the disk that you choose. Are you sure you want to run it?"

## Find all possible disks
possible_disks=$(lsblk --raw --paths --output NAME,MODEL,SIZE,TYPE | grep "disk" | awk '{ print $1 " " $2 "(" $3 ")" }')

## Make user select a disk
selected_disk=$(dialog \
	--stdout \
	--title "Select disk to partition" \
	--menu "
	Select a disk to partition with the following partitions:
       
	- EFI-System partition (512MB)
       	- Root partition (32GB)
	- Home partition (Remaining space)
       	- Swap partition (8GB)" \
	0 60 0 \
	$possible_disks \
	1>&3)

is_mounted=$(lsblk --raw --paths --noheadings --output MOUNTPOINT "$selected_disk")
[[ ! -z $is_mounted ]] && { dialog_error "$selected_disk is already mounted. Please unmount it before trying to partition it"; exit 1; }

dialog_warning "Zb\Z3\Zr $selected_disk \Zn will be \Zb\Z3\Zr fully erased and overwritten \Zn with a new GPT partition table. Still sure?"

efi_part="$selected_disk$EFI_DEV_NR"
root_part="$selected_disk$ROOT_DEV_NR"
home_part="$selected_disk$HOME_DEV_NR"
swap_part="$selected_disk$SWAP_DEV_NR"

log "Creating partitions"
cat <<EOF | gdisk "$selected_disk"
o
y
n
${EFI_DEV_NR}

+${EFI_SIZE}
EF00
n
${ROOT_DEV_NR}

+${ROOT_SIZE}
8304
n
${SWAP_DEV_NR}
-${SWAP_SIZE}

8200
n
${HOME_DEV_NR}


8302
w
y
EOF

log "Probing partitions to update active partition table..."
partprobe

log "Formatting partitions..."
mkfs.fat -F 32 -n "ARCH_EFI" "$efi_part"
mkfs.ext4 -F -q -L "Linux_x86-64_(/)" "$root_part"
mkfs.ext4 -F -q -L "Linux_/home" "$home_part"
mkswap -L "Linux_swap" -c "$swap_part"

log "Mounting partitons..."
swapon "$swap_part"
mount "$root_part" /mnt
mkdir -p /mnt/home
mkdir -p /mnt/boot 
mount "$efi_part" /mnt/boot 
mount "$home_part" /mnt/home 

log "Successfully partitionned and mounted $selected_disk\n\n$(lsblk --output NAME,SIZE,MOUNTPOINT $selected_disk)"

### Do the actual installation ###
##################################

pacstrap /mnt ${BASE_PKGS[@]} 

# Generate fstab
genfstab -U /mnt >>/mnt/etc/fstab

### Run a script as chroot in the newly made installation ###
#############################################################

get_file "dist/bassal_chroot.sh" 
mv "$__" "/mnt/$__"
arch-chroot /mnt bash "$__"
rm "/mnt/$__"

