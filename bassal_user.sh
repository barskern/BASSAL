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

### Install packages from AUR ###
#################################

install_aur_pkgs() {
	command -v packer || {
		tmp_dir=$(mktemp -d)
		git clone -q https://aur.archlinux.org/packer.git $tmp_dir
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

	command -v packer || { dialog_error "Packer did not install successfully, please install it manually and then rerun script"; exit 1; }

	install_aur_pkg() {
		local pkg=$1
		packer -S --noconfirm --noedit "$pkg"
	}

	get_file "data/packages_aur.csv"
	pkgs_aur_file=${__}

	readarray pkgs_aur <<< "$(cat "$pkgs_aur_file" | cut -d ',' -f 1)"

	map_with_status "Building and installing packages from AUR" install_aur_pkg pkgs_aur[@]
}
install_aur_pkgs

### Download dotfiles with homesick ###
#######################################

setup_dotfiles() {
	# Make sure that ruby is installed
	[[ -z "$(pacman -Q ruby)" ]] && { display_error "Ruby has to be installed to run this script"; exit 1; }

	log "Installing homesick with gem..."
	gem install homesick --no-document

	homesick_cmd="$(ruby -e 'print Gem.user_dir')/bin/homesick"

	log "Cloning and linking castle $HOMESICK_CASTLE from $GITHUB_USER's github user..."
	$homesick_cmd clone "$GITHUB_USER/$HOMESICK_CASTLE"
	$homesick_cmd link "$HOMESICK_CASTLE"
}
setup_dotfiles

### Configure user-environement ###
###################################

log "Downloading and installing antigen.."
mkdir -p $HOME/.config
curl -F git.io/antigen > $HOME/.config/antigen.zsh

log "Adding .gitaliases to .gitconfig"
echo -e "
[include]
	path = $HOME/.gitaliases
" >> $HOME/.gitconfig

### Startup systemd-scripts ###
###############################

systemctl --user enable mpd
systemctl --user enable pulseaudio
systemctl --user enable compton
