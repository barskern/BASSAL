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

### Install packages from AUR ###
#################################

install_aur_pkgs() {
	command -v yay || {
		tmp_dir=$(mktemp -d)
		git clone -q https://aur.archlinux.org/yay.git $tmp_dir
		cd "$tmp_dir"
		makepkg --clean \
			--install \
			--rmdeps \
			--syncdeps \
			--needed \
			--noconfirm \
			--noprogressbar
		cd -
	}

	command -v yay || { dialog_error "Packer did not install successfully, please install it manually and then rerun script"; exit 1; }

	install_aur_pkg() {
		local pkg=$1
		yay -S --noconfirm "$pkg"
	}

	get_file "data/packages_aur.csv"
	readarray pkgs_aur <<< "$(cat "$__" | cut -d ',' -f 1)"
	rm "$__"

	map_with_status "Building and installing packages from AUR" install_aur_pkg pkgs_aur[@]
}
install_aur_pkgs

### Download dotfiles with homesick ###
#######################################

mkdir -p $HOME/.config
git clone --git-dir=$HOME/.config/dotfiles --work-tree=$HOME https://github.com/barskern/dotfiles $HOME/.config/dotfiles

### Configure user-environement ###
###################################

log "Downloading and installing antigen.."
curl -F git.io/antigen > $HOME/.config/antigen.zsh

log "Adding git aliases to git config"
echo -e "
[include]
	path = $HOME/.config/git/aliases
" >> $HOME/.config/git/config

### Configure lightdm ###
#########################
# PS! Has to be done after user setup because lightdm-mini-greeter
# is installed from the AUR, hence cannot be installed as root

sed -i -e "s/^#\?greeter-session=.*$/greeter-session=lightdm-mini-greeter/" /etc/lightdm/lightdm.conf
sed -i -e "s/^#\?user-session=.*$/user-session=i3-sd/" /etc/lightdm/lightdm.conf

sed -i -e "s/^user\s=.*$/user = $username/" /etc/lightdm/lightdm-mini-greeter.conf
sed -i -e "s/^window-color\s=.*$/window-color = \"#F1F1F1\"/" /etc/lightdm/lightdm-mini-greeter.conf
sed -i -e "s,^background-image\s=.*$,background-image = \"/usr/share/backgrounds/login-wall.png\"," /etc/lightdm/lightdm-mini-greeter.conf

dialog_message \
	"Lightdm background" \
	"Add an image to \"/usr/share/backgrounds/login-wall.png\" to use as a background for the lightdm-mini-greeter"

clear
