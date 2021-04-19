#!/bin/sh
#-
# Copyright (c) 2013-2016 Allan Jude
# Copyright (c) 2013-2015 Devin Teske
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#
# $FreeBSD$
#
############################################################ INCLUDES

BSDCFG_SHARE="/usr/share/bsdconfig"
. $BSDCFG_SHARE/common.subr || exit 1
f_dprintf "%s: loading includes..." "$0"
f_include $BSDCFG_SHARE/device.subr
f_include $BSDCFG_SHARE/dialog.subr
f_include $BSDCFG_SHARE/password/password.subr
f_include $BSDCFG_SHARE/variable.subr

############################################################ CONFIGURATION

#
# Default name of the boot-pool
#
: ${ZFSBOOT_POOL_NAME:=zroot}

#
# Default options to use when creating zroot pool
#
: ${ZFSBOOT_POOL_CREATE_OPTIONS:=-O compress=lz4 -O atime=off}

#
# Default name for the boot environment parent dataset
#
: ${ZFSBOOT_BEROOT_NAME:=ROOT}

#
# Default name for the primary boot environment
#
: ${ZFSBOOT_BOOTFS_NAME:=default}

#
# Default Virtual Device (vdev) type to create
#
: ${ZFSBOOT_VDEV_TYPE:=stripe}

#
# Should we use sysctl(8) vfs.zfs.min_auto_ashift=12 to force 4K sectors?
#
: ${ZFSBOOT_FORCE_4K_SECTORS:=1}

#
# Should we use geli(8) to encrypt the drives?
# NB: Automatically enables ZFSBOOT_BOOT_POOL
#
: ${ZFSBOOT_GELI_ENCRYPTION=}

#
# Default path to the geli(8) keyfile used in drive encryption
#
: ${ZFSBOOT_GELI_KEY_FILE:=/boot/encryption.key}

#
# Create a separate boot pool?
# NB: Automatically set when using geli(8) or MBR
#
: ${ZFSBOOT_BOOT_POOL=}

#
# Options to use when creating separate boot pool (if any)
#
: ${ZFSBOOT_BOOT_POOL_CREATE_OPTIONS:=}

#
# Default name for boot pool when enabled (e.g., geli(8) or MBR)
#
: ${ZFSBOOT_BOOT_POOL_NAME:=bootpool}

#
# Default size for boot pool when enabled (e.g., geli(8) or MBR)
#
: ${ZFSBOOT_BOOT_POOL_SIZE:=2g}

#
# Default disks to use (always empty unless being scripted)
#
: ${ZFSBOOT_DISKS:=}

#
# Default partitioning scheme to use on disks
#
: ${ZFSBOOT_PARTITION_SCHEME:=}

#
# Default boot type to use on disks
#
: ${ZFSBOOT_BOOT_TYPE:=}

#
# How much swap to put on each block device in the boot zpool
# NOTE: Value passed to gpart(8); which supports SI unit suffixes.
#
: ${ZFSBOOT_SWAP_SIZE:=8g}

#
# Should we use geli(8) to encrypt the swap?
#
: ${ZFSBOOT_SWAP_ENCRYPTION=}

#
# Should we use gmirror(8) to mirror the swap?
#
: ${ZFSBOOT_SWAP_MIRROR=}

#
# Default ZFS datasets for root zpool
#
# NOTE: Requires /tmp, /var/tmp, /$ZFSBOOT_BOOTFS_NAME/$ZFSBOOT_BOOTFS_NAME
# NOTE: Anything after pound/hash character [#] is ignored as a comment.
#
f_isset ZFSBOOT_DATASETS || ZFSBOOT_DATASETS="
	# DATASET	OPTIONS (comma or space separated; or both)

	# Boot Environment [BE] root and default boot dataset
	/$ZFSBOOT_BEROOT_NAME				mountpoint=none
	/$ZFSBOOT_BEROOT_NAME/$ZFSBOOT_BOOTFS_NAME	mountpoint=/

	# Compress /tmp, allow exec but not setuid
	/tmp		mountpoint=/tmp,exec=on,setuid=off

	# Don't mount /usr so that 'base' files go to the BEROOT
	/usr		mountpoint=/usr,canmount=off

	# Home directories separated so they are common to all BEs
	/usr/home	# NB: /home is a symlink to /usr/home

	# Ports tree
	/usr/ports	setuid=off

	# Source tree (compressed)
	/usr/src

	# Create /var and friends
	/var		mountpoint=/var,canmount=off
	/var/audit	exec=off,setuid=off
	/var/crash	exec=off,setuid=off
	/var/log	exec=off,setuid=off
	/var/mail	atime=on
	/var/tmp	setuid=off
" # END-QUOTE

#
# If interactive and the user has not explicitly chosen a vdev type or disks,
# make the user confirm scripted/default choices when proceeding to install.
#
: ${ZFSBOOT_CONFIRM_LAYOUT:=1}

############################################################ GLOBALS

#
# Format of a line in printf(1) syntax to add to fstab(5)
#
FSTAB_FMT="%s\t\t%s\t%s\t%s\t\t%s\t%s\n"

#
# Command strings for various tasks
#
COPY='cp "%s" "%s"'
CHMOD_MODE='chmod %s "%s"'
DD_WITH_OPTIONS='dd if="%s" of="%s" %s'
ECHO_APPEND='echo "%s" >> "%s"'
ECHO_OVERWRITE='echo "%s" > "%s"'
GELI_ATTACH='geli attach -j - -k "%s" "%s"'
GELI_ATTACH_NOKEY='geli attach -j - "%s"'
GELI_DETACH_F='geli detach -f "%s"'
GELI_PASSWORD_INIT='geli init -b -B "%s" -e %s -J - -K "%s" -l 256 -s 4096 "%s"'
GELI_PASSWORD_GELIBOOT_INIT='geli init -bg -e %s -J - -l 256 -s 4096 "%s"'
GPART_ADD_ALIGN='gpart add %s -t %s "%s"'
GPART_ADD_ALIGN_INDEX='gpart add %s -i %s -t %s "%s"'
GPART_ADD_ALIGN_INDEX_WITH_SIZE='gpart add %s -i %s -t %s -s %s "%s"'
GPART_ADD_ALIGN_LABEL='gpart add %s -l %s -t %s "%s"'
GPART_ADD_ALIGN_LABEL_WITH_SIZE='gpart add %s -l %s -t %s -s %s "%s"'
GPART_BOOTCODE='gpart bootcode -b "%s" "%s"'
GPART_BOOTCODE_PART='gpart bootcode -b "%s" -p "%s" -i %s "%s"'
GPART_BOOTCODE_PARTONLY='gpart bootcode -p "%s" -i %s "%s"'
GPART_CREATE='gpart create -s %s "%s"'
GPART_DESTROY_F='gpart destroy -F "%s"'
GPART_SET_ACTIVE='gpart set -a active -i %s "%s"'
GPART_SET_LENOVOFIX='gpart set -a lenovofix "%s"'
GPART_SET_PMBR_ACTIVE='gpart set -a active "%s"'
GRAID_DELETE='graid delete "%s"'
KLDLOAD='kldload %s'
LN_SF='ln -sf "%s" "%s"'
MKDIR_P='mkdir -p "%s"'
MOUNT_TYPE='mount -t %s "%s" "%s"'
NEWFS_ESP='newfs_msdos -F %s -L "%s" "%s"'
PRINTF_CONF="printf '%s=\"%%s\"\\\n' %s >> \"%s\""
PRINTF_FSTAB='printf "$FSTAB_FMT" "%s" "%s" "%s" "%s" "%s" "%s" >> "%s"'
SHELL_TRUNCATE=':> "%s"'
SWAP_GMIRROR_LABEL='gmirror label swap %s'
SYSCTL_ZFS_MIN_ASHIFT_12='sysctl vfs.zfs.min_auto_ashift=12'
UMOUNT='umount "%s"'
ZFS_CREATE_WITH_OPTIONS='zfs create %s "%s"'
ZFS_MOUNT='zfs mount "%s"'
ZFS_SET='zfs set "%s" "%s"'
ZFS_UNMOUNT='zfs unmount "%s"'
ZPOOL_CREATE_WITH_OPTIONS='zpool create %s "%s" %s %s'
ZPOOL_DESTROY='zpool destroy "%s"'
ZPOOL_EXPORT='zpool export "%s"'
ZPOOL_EXPORT_F='zpool export -f "%s"'
ZPOOL_IMPORT_WITH_OPTIONS='zpool import %s "%s"'
ZPOOL_LABELCLEAR_F='zpool labelclear -f "%s"'
ZPOOL_SET='zpool set %s "%s"'

#
# Strings that should be moved to an i18n file and loaded with f_include_lang()
#
hline_alnum_arrows_punc_tab_enter="Use alnum, arrows, punctuation, TAB or ENTER"
hline_arrows_space_tab_enter="Use arrows, SPACE, TAB or ENTER"
hline_arrows_tab_enter="Press arrows, TAB or ENTER"
msg_an_unknown_error_occurred="An unknown error occurred"
msg_back="Back"
msg_cancel="Cancel"
msg_change_selection="Change Selection"
msg_configure_options="Configure Options:"
msg_detailed_disk_info="gpart(8) show %s:\n%s\n\ncamcontrol(8) inquiry %s:\n%s\n\n\ncamcontrol(8) identify %s:\n%s\n"
msg_disk_info="Disk Info"
msg_disk_info_help="Get detailed information on disk device(s)"
msg_disk_singular="disk"
msg_disk_plural="disks"
msg_encrypt_disks="Encrypt Disks?"
msg_encrypt_disks_help="Use geli(8) to encrypt all data partitions"
msg_error="Error"
msg_force_4k_sectors="Force 4K Sectors?"
msg_force_4k_sectors_help="Align partitions to 4K sector boundries and set vfs.zfs.min_auto_ashift=12"
msg_freebsd_installer="OPNsense Installer"
msg_geli_password="Enter a strong passphrase, used to protect your encryption keys. You will be required to enter this passphrase each time the system is booted"
msg_geli_setup="Initializing encryption on selected disks,\n this will take several seconds per disk"
msg_install="Install"
msg_install_desc="Proceed with Installation"
msg_install_help="Create ZFS boot pool with displayed options"
msg_invalid_boot_pool_size="Invalid boot pool size \`%s'"
msg_invalid_disk_argument="Invalid disk argument \`%s'"
msg_invalid_index_argument="Invalid index argument \`%s'"
msg_invalid_swap_size="Invalid swap size \`%s'"
msg_invalid_virtual_device_type="Invalid Virtual Device type \`%s'"
msg_last_chance_are_you_sure="Last Chance! Are you sure you want to destroy\nthe current contents of the following disks:\n\n   %s"
msg_last_chance_are_you_sure_color='\\ZrLast Chance!\\ZR Are you \\Z1sure\\Zn you want to \\Zr\\Z1destroy\\Zn\nthe current contents of the following disks:\n\n   %s'
msg_mirror_desc="Mirror - n-Way Mirroring"
msg_mirror_help="[2+ Disks] Mirroring provides the best performance, but the least storage"
msg_missing_disk_arguments="missing disk arguments"
msg_missing_one_or_more_scripted_disks="Missing one or more scripted disks!"
msg_no="NO"
msg_no_disks_present_to_configure="No disk(s) present to configure"
msg_no_disks_selected="No disks selected."
msg_not_enough_disks_selected="Not enough disks selected. (%u < %u minimum)"
msg_null_disk_argument="NULL disk argument"
msg_null_index_argument="NULL index argument"
msg_null_poolname="NULL poolname"
msg_odd_disk_selected="An even number of disks must be selected to create a RAID 1+0. (%u selected)"
msg_ok="OK"
msg_partition_scheme="Partition Scheme"
msg_partition_scheme_help="Select partitioning scheme. GPT is recommended."
msg_please_enter_a_name_for_your_zpool="Please enter a name for your zpool:"
msg_please_enter_amount_of_swap_space="Please enter amount of swap space (SI-Unit suffixes\nrecommended; e.g., \`2g' for 2 Gigabytes):"
msg_please_select_one_or_more_disks="Please select one or more disks to create a zpool:"
msg_pool_name="Pool Name"
msg_pool_name_cannot_be_empty="Pool name cannot be empty."
msg_pool_name_help="Customize the name of the zpool to be created (Required)"
msg_pool_type_disks="Pool Type/Disks:"
msg_pool_type_disks_help="Choose type of ZFS Virtual Device and disks to use (Required)"
msg_processing_selection="Processing selection..."
msg_raid10_desc="RAID 1+0 - n x 2-Way Mirrors"
msg_raid10_help="[4+ Disks] Striped Mirrors provides the best performance, but the least storage"
msg_raidz1_desc="RAID-Z1 - Single Redundant RAID"
msg_raidz1_help="[3+ Disks] Withstand failure of 1 disk. Recommended for: 3, 5 or 9 disks"
msg_raidz2_desc="RAID-Z2 - Double Redundant RAID"
msg_raidz2_help="[4+ Disks] Withstand failure of 2 disks. Recommended for: 4, 6 or 10 disks"
msg_raidz3_desc="RAID-Z3 - Triple Redundant RAID"
msg_raidz3_help="[5+ Disks] Withstand failure of 3 disks. Recommended for: 5, 7 or 11 disks"
msg_rescan_devices="Rescan Devices"
msg_rescan_devices_help="Scan for device changes"
msg_select="Select"
msg_select_a_disk_device="Select a disk device"
msg_select_virtual_device_type="Select Virtual Device type:"
msg_stripe_desc="Stripe - No Redundancy"
msg_stripe_help="[1+ Disks] Striping provides maximum storage but no redundancy"
msg_swap_encrypt="Encrypt Swap?"
msg_swap_encrypt_help="Encrypt swap partitions with temporary keys, discarded on reboot"
msg_swap_invalid="The selected swap size (%s) is invalid. Enter a number optionally followed by units. Example: 2G"
msg_swap_mirror="Mirror Swap?"
msg_swap_mirror_help="Mirror swap partitions for redundancy, breaks crash dumps"
msg_swap_size="Swap Size"
msg_swap_size_help="Customize how much swap space is allocated to each selected disk"
msg_swap_toosmall="The selected swap size (%s) is to small. Please enter a value greater than 100MB or enter 0 for no swap"
msg_these_disks_are_too_small="These disks are smaller than the amount of requested\nswap (%s) and/or geli(8) (%s) partitions, which would\ntake 100%% or more of each of the following selected disks:\n\n  %s\n\nRecommend changing partition size(s) and/or selecting a\ndifferent set of disks."
msg_unable_to_get_disk_capacity="Unable to get disk capacity of \`%s'"
msg_unsupported_partition_scheme="%s is an unsupported partition scheme"
msg_user_cancelled="User Cancelled."
msg_yes="YES"
msg_zfs_configuration="ZFS Configuration"

############################################################ FUNCTIONS

# dialog_menu_main
#
# Display the dialog(1)-based application main menu.
#
dialog_menu_main()
{
	local title="$DIALOG_TITLE"
	local btitle="$DIALOG_BACKTITLE"
	local prompt="$msg_configure_options"
	local force4k="$msg_no"
	local usegeli="$msg_no"
	local swapgeli="$msg_no"
	local swapmirror="$msg_no"
	[ "$ZFSBOOT_FORCE_4K_SECTORS" ] && force4k="$msg_yes"
	[ "$ZFSBOOT_GELI_ENCRYPTION" ] && usegeli="$msg_yes"
	[ "$ZFSBOOT_SWAP_ENCRYPTION" ] && swapgeli="$msg_yes"
	[ "$ZFSBOOT_SWAP_MIRROR" ] && swapmirror="$msg_yes"
	local disks n disks_grammar
	f_count n $ZFSBOOT_DISKS
	{ [ $n -eq 1 ] && disks_grammar=$msg_disk_singular; } ||
		disks_grammar=$msg_disk_plural # grammar
	local menu_list="
		'>>> $msg_install'      '$msg_install_desc'
		                        '$msg_install_help'
		'T $msg_pool_type_disks'
		                        '$ZFSBOOT_VDEV_TYPE: $n $disks_grammar'
		                        '$msg_pool_type_disks_help'
		'- $msg_rescan_devices' '*'
		                        '$msg_rescan_devices_help'
		'- $msg_disk_info'      '*'
		                        '$msg_disk_info_help'
		'N $msg_pool_name'      '$ZFSBOOT_POOL_NAME'
		                        '$msg_pool_name_help'
		'4 $msg_force_4k_sectors'
		                        '$force4k'
		                        '$msg_force_4k_sectors_help'
		'E $msg_encrypt_disks'  '$usegeli'
		                        '$msg_encrypt_disks_help'
		'P $msg_partition_scheme'
		                        '$ZFSBOOT_PARTITION_SCHEME ($ZFSBOOT_BOOT_TYPE)'
		                        '$msg_partition_scheme_help'
		'S $msg_swap_size'      '$ZFSBOOT_SWAP_SIZE'
		                        '$msg_swap_size_help'
		'M $msg_swap_mirror'    '$swapmirror'
		                        '$msg_swap_mirror_help'
		'W $msg_swap_encrypt'   '$swapgeli'
		                        '$msg_swap_encrypt_help'
	" # END-QUOTE
	local defaultitem= # Calculated below
	local hline="$hline_alnum_arrows_punc_tab_enter"

	local height width rows
	eval f_dialog_menu_with_help_size height width rows \
		\"\$title\" \"\$btitle\" \"\$prompt\" \"\$hline\" $menu_list

	# Obtain default-item from previously stored selection
	f_dialog_default_fetch defaultitem

	local menu_choice
	menu_choice=$( eval $DIALOG \
		--title \"\$title\"              \
		--backtitle \"\$btitle\"         \
		--hline \"\$hline\"              \
		--item-help                      \
		--ok-label \"\$msg_select\"      \
		--cancel-label \"\$msg_cancel\"  \
		--default-item \"\$defaultitem\" \
		--menu \"\$prompt\"              \
		$height $width $rows             \
		$menu_list                       \
		2>&1 >&$DIALOG_TERMINAL_PASSTHRU_FD
	)
	local retval=$?
	f_dialog_data_sanitize menu_choice
	f_dialog_menutag_store "$menu_choice"

	# Only update default-item on success
	[ $retval -eq $DIALOG_OK ] && f_dialog_default_store "$menu_choice"

	return $retval
}

# dialog_last_chance $disks ...
#
# Display a list of the disks that the user is about to destroy. The default
# action is to return error status unless the user explicitly (non-default)
# selects "Yes" from the noyes dialog.
#
dialog_last_chance()
{
	local title="$DIALOG_TITLE"
	local btitle="$DIALOG_BACKTITLE"
	local prompt # Calculated below
	local hline="$hline_arrows_tab_enter"

	local height=8 width=50 prefix="   "
	local plen=${#prefix} list= line=
	local max_width=$(( $width - 3 - $plen ))

	local yes no defaultno extra_args format
	if [ "$USE_XDIALOG" ]; then
		yes=ok no=cancel defaultno=default-no
		extra_args="--wrap --left"
		format="$msg_last_chance_are_you_sure"
	else
		yes=yes no=no defaultno=defaultno
		extra_args="--colors --cr-wrap"
		format="$msg_last_chance_are_you_sure_color"
	fi

	local disk line_width
	for disk in $*; do
		if [ "$line" ]; then
			line_width=${#line}
		else
			line_width=$plen
		fi
		line_width=$(( $line_width + 1 + ${#disk} ))
		# Add newline before disk if it would exceed max_width
		if [ $line_width -gt $max_width ]; then
			list="$list$line\n"
			line="$prefix"
			height=$(( $height + 1 ))
		fi
		# Add the disk to the list
		line="$line $disk"
	done
	# Append the left-overs
	if [ "${line#$prefix}" ]; then
		list="$list$line"
		height=$(( $height + 1 ))
	fi

	# Add height for Xdialog(1)
	[ "$USE_XDIALOG" ] && height=$(( $height + $height / 5 + 3 ))

	prompt=$( printf "$format" "$list" )
	f_dprintf "%s: Last Chance!" "$0"
	$DIALOG \
		--title "$title"        \
		--backtitle "$btitle"   \
		--hline "$hline"        \
		--$defaultno            \
		--$yes-label "$msg_yes" \
		--$no-label "$msg_no"   \
		$extra_args             \
		--yesno "$prompt" $height $width
}

# dialog_menu_layout
#
# Configure Virtual Device type and disks to use for the ZFS boot pool. User
# must select enough disks to satisfy the chosen vdev type.
#
dialog_menu_layout()
{
	local funcname=dialog_menu_layout
	local title="$DIALOG_TITLE"
	local btitle="$DIALOG_BACKTITLE"
	local vdev_prompt="$msg_select_virtual_device_type"
	local disk_prompt="$msg_please_select_one_or_more_disks"
	local vdev_menu_list="
		'stripe' '$msg_stripe_desc' '$msg_stripe_help'
		'mirror' '$msg_mirror_desc' '$msg_mirror_help'
		'raid10' '$msg_raid10_desc' '$msg_raid10_help'
		'raidz1' '$msg_raidz1_desc' '$msg_raidz1_help'
		'raidz2' '$msg_raidz2_desc' '$msg_raidz2_help'
		'raidz3' '$msg_raidz3_desc' '$msg_raidz3_help'
	" # END-QUOTE
	local disk_check_list= # Calculated below
	local vdev_hline="$hline_arrows_tab_enter"
	local disk_hline="$hline_arrows_space_tab_enter"

	# Warn the user if vdev type is not valid
	case "$ZFSBOOT_VDEV_TYPE" in
	stripe|mirror|raid10|raidz1|raidz2|raidz3) : known good ;;
	*)
		f_dprintf "%s: Invalid virtual device type \`%s'" \
			  $funcname "$ZFSBOOT_VDEV_TYPE"
		f_show_err "$msg_invalid_virtual_device_type" \
			   "$ZFSBOOT_VDEV_TYPE"
		f_interactive || return $FAILURE
	esac

	# Calculate size of vdev menu once only
	local vheight vwidth vrows
	eval f_dialog_menu_with_help_size vheight vwidth vrows \
		\"\$title\" \"\$btitle\" \"\$vdev_prompt\" \"\$vdev_hline\" \
		$vdev_menu_list

	# Get a list of probed disk devices
	local disks=
	debug= f_device_find "" $DEVICE_TYPE_DISK disks

	# Prune out mounted md(4) devices that may be part of the boot process
	local disk name new_list=
	for disk in $disks; do
		debug= $disk get name name
		case "$name" in
		md[0-9]*) f_mounted -b "/dev/$name" && continue ;;
		esac
		new_list="$new_list $disk"
	done
	disks="${new_list# }"

	# Debugging
	if [ "$debug" ]; then
		local disk_names=
		for disk in $disks; do
			debug= $disk get name name
			disk_names="$disk_names $name"
		done
		f_dprintf "$funcname: disks=[%s]" "${disk_names# }"
	fi

	if [ ! "$disks" ]; then
		f_dprintf "No disk(s) present to configure"
		f_show_err "$msg_no_disks_present_to_configure"
		return $FAILURE
	fi

	# Lets sort the disks array to be more user friendly
	f_device_sort_by name disks disks

	#
	# Operate in a loop so we can (if interactive) repeat if not enough
	# disks are selected to satisfy the chosen vdev type or user wants to
	# back-up to the previous menu.
	#
	local vardisk ndisks onoff selections vdev_choice breakout device
	local valid_disks all_valid want_disks desc height width rows
	while :; do
		#
		# Confirm the vdev type that was selected
		#
		if f_interactive && [ "$ZFSBOOT_CONFIRM_LAYOUT" ]; then
			vdev_choice=$( eval $DIALOG \
				--title \"\$title\"              \
				--backtitle \"\$btitle\"         \
				--hline \"\$vdev_hline\"         \
				--ok-label \"\$msg_ok\"          \
				--cancel-label \"\$msg_cancel\"  \
				--item-help                      \
				--default-item \"\$ZFSBOOT_VDEV_TYPE\" \
				--menu \"\$vdev_prompt\"         \
				$vheight $vwidth $vrows          \
				$vdev_menu_list                  \
				2>&1 >&$DIALOG_TERMINAL_PASSTHRU_FD
			) || return $?
				# Exit if user pressed ESC or chose Cancel/No
			f_dialog_data_sanitize vdev_choice

			ZFSBOOT_VDEV_TYPE="$vdev_choice"
			f_dprintf "$funcname: ZFSBOOT_VDEV_TYPE=[%s]" \
			          "$ZFSBOOT_VDEV_TYPE"
		fi

		# Determine the number of disks needed for this vdev type
		want_disks=0
		case "$ZFSBOOT_VDEV_TYPE" in
		stripe) want_disks=1 ;;
		mirror) want_disks=2 ;;
		raid10) want_disks=4 ;;
		raidz1) want_disks=3 ;;
		raidz2) want_disks=4 ;;
		raidz3) want_disks=5 ;;
		esac

		#
		# Warn the user if any scripted disks are invalid
		#
		valid_disks= all_valid=${ZFSBOOT_DISKS:+1} # optimism
		for disk in $ZFSBOOT_DISKS; do
			if debug= f_device_find -1 \
				$disk $DEVICE_TYPE_DISK device
			then
				valid_disks="$valid_disks $disk"
				continue
			fi
			f_dprintf "$funcname: \`%s' is not a real disk" "$disk"
			all_valid=
		done
		if [ ! "$all_valid" ]; then
			if [ "$ZFSBOOT_DISKS" ]; then
				f_show_err \
				    "$msg_missing_one_or_more_scripted_disks"
			else
				f_dprintf "No disks selected."
				f_interactive ||
					f_show_err "$msg_no_disks_selected"
			fi
			f_interactive || return $FAILURE
		fi
		ZFSBOOT_DISKS="${valid_disks# }"

		#
		# Short-circuit if we're running non-interactively
		#
		if ! f_interactive || [ ! "$ZFSBOOT_CONFIRM_LAYOUT" ]; then
			f_count ndisks $ZFSBOOT_DISKS
			[ $ndisks -ge $want_disks ] && break # to success

			# Not enough disks selected
			f_dprintf "$funcname: %s: %s (%u < %u minimum)" \
				  "$ZFSBOOT_VDEV_TYPE" \
			          "Not enough disks selected." \
				  $ndisks $want_disks
			f_interactive || return $FAILURE
			msg_yes="$msg_change_selection" msg_no="$msg_cancel" \
				f_yesno "%s: $msg_not_enough_disks_selected" \
				"$ZFSBOOT_VDEV_TYPE" $ndisks $want_disks ||
				return $FAILURE
		fi

		#
		# Confirm the disks that were selected
		# Loop until the user cancels or selects enough disks
		#
		breakout=
		while :; do
			# Loop over list of available disks, resetting state
			for disk in $disks; do
				f_isset _${disk}_status && _${disk}_status=
			done

			# Loop over list of selected disks and create temporary
			# locals to map statuses onto up-to-date list of disks
			for disk in $ZFSBOOT_DISKS; do
				debug= f_device_find -1 \
					$disk $DEVICE_TYPE_DISK disk
				f_isset _${disk}_status ||
					local _${disk}_status
				_${disk}_status=on
			done

			# Create the checklist menu of discovered disk devices
			disk_check_list=
			for disk in $disks; do
				desc=
				$disk get name name
				$disk get desc desc
				f_shell_escape "$desc" desc
				f_getvar _${disk}_status:-off onoff
				disk_check_list="$disk_check_list
					$name '$desc' $onoff"
			done

			eval f_dialog_checklist_size height width rows \
				\"\$title\" \"\$btitle\" \"\$prompt\" \
				\"\$hline\" $disk_check_list

			selections=$( eval $DIALOG \
				--title \"\$DIALOG_TITLE\"         \
				--backtitle \"\$DIALOG_BACKTITLE\" \
				--separate-output                  \
				--hline \"\$hline\"                \
				--ok-label \"\$msg_ok\"            \
				--cancel-label \"\$msg_back\"      \
				--checklist \"\$prompt\"           \
				$height $width $rows               \
				$disk_check_list                   \
				2>&1 >&$DIALOG_TERMINAL_PASSTHRU_FD
			) || break
				# Loop if user pressed ESC or chose Cancel/No
			f_dialog_data_sanitize selections

			ZFSBOOT_DISKS="$selections"
			f_dprintf "$funcname: ZFSBOOT_DISKS=[%s]" \
			          "$ZFSBOOT_DISKS"

			f_count ndisks $ZFSBOOT_DISKS

			if [ "$ZFSBOOT_VDEV_TYPE" == "raid10" ] &&
			    [ $(( $ndisks % 2 )) -ne 0 ]; then
				f_dprintf "$funcname: %s: %s (%u %% 2 = %u)" \
					  "$ZFSBOOT_VDEV_TYPE" \
					  "Number of disks not even:" \
					  $ndisks $(( $ndisks % 2 ))
				msg_yes="$msg_change_selection" \
					msg_no="$msg_cancel" \
					f_yesno "%s: $msg_odd_disk_selected" \
						"$ZFSBOOT_VDEV_TYPE" $ndisks ||
						break
				continue
			fi

			[ $ndisks -ge $want_disks ] &&
				breakout=break && break

			# Not enough disks selected
			f_dprintf "$funcname: %s: %s (%u < %u minimum)" \
				  "$ZFSBOOT_VDEV_TYPE" \
			          "Not enough disks selected." \
			          $ndisks $want_disks
			msg_yes="$msg_change_selection" msg_no="$msg_cancel" \
				f_yesno "%s: $msg_not_enough_disks_selected" \
				"$ZFSBOOT_VDEV_TYPE" $ndisks $want_disks ||
				break
		done
		[ "$breakout" = "break" ] && break
		[ "$ZFSBOOT_CONFIRM_LAYOUT" ] || return $FAILURE
	done

	return $DIALOG_OK
}

# zfs_create_diskpart $disk $index
#
# For each block device to be used in the zpool, rather than just create the
# zpool with the raw block devices (e.g., da0, da1, etc.) we create partitions
# so we can have some real swap. This also provides wiggle room incase your
# replacement drivers do not have the exact same sector counts.
#
# NOTE: $swapsize and $bootsize should be defined by the calling function.
# NOTE: Sets $bootpart and $targetpart for the calling function.
#
zfs_create_diskpart()
{
	local funcname=zfs_create_diskpart
	local disk="$1" index="$2"

	# Check arguments
	if [ ! "$disk" ]; then
		f_dprintf "$funcname: NULL disk argument"
		msg_error="$msg_error: $funcname" \
			f_show_err "$msg_null_disk_argument"
		return $FAILURE
	fi
	if [ "${disk#*[$IFS]}" != "$disk" ]; then
		f_dprintf "$funcname: Invalid disk argument \`%s'" "$disk"
		msg_error="$msg_error: $funcname" \
			f_show_err "$msg_invalid_disk_argument" "$disk"
		return $FAILURE
	fi
	if [ ! "$index" ]; then
		f_dprintf "$funcname: NULL index argument"
		msg_error="$msg_error: $funcname" \
			f_show_err "$msg_null_index_argument"
		return $FAILURE
	fi
	if ! f_isinteger "$index"; then
		f_dprintf "$funcname: Invalid index argument \`%s'" "$index"
		msg_error="$msg_error: $funcname" \
			f_show_err "$msg_invalid_index_argument" "$index"
		return $FAILURE
	fi
	f_dprintf "$funcname: disk=[%s] index=[%s]" "$disk" "$index"

	# Check for unknown partition scheme before proceeding further
	case "$ZFSBOOT_PARTITION_SCHEME" in
	""|MBR|GPT*) : known good ;;
	*)
		f_dprintf "$funcname: %s is an unsupported partition scheme" \
		          "$ZFSBOOT_PARTITION_SCHEME"
		msg_error="$msg_error: $funcname" f_show_err \
			"$msg_unsupported_partition_scheme" \
			"$ZFSBOOT_PARTITION_SCHEME"
		return $FAILURE
	esac

	#
	# Destroy whatever partition layout is currently on disk.
	# NOTE: `-F' required to destroy if partitions still exist.
	# NOTE: Failure is ok here, blank disk will have nothing to destroy.
	#
	f_dprintf "$funcname: Exporting ZFS pools..."
	zpool list -Ho name | while read z_name; do
		f_eval_catch -d $funcname zpool "$ZPOOL_EXPORT_F" $z_name
	done
	f_dprintf "$funcname: Detaching all GELI providers..."
	geli status | tail -n +2 | while read g_name g_status g_component; do
		f_eval_catch -d $funcname geli "$GELI_DETACH_F" $g_name
	done
	f_dprintf "$funcname: Destroying all data/layouts on \`%s'..." "$disk"
	f_eval_catch -d $funcname gpart "$GPART_DESTROY_F" $disk
	f_eval_catch -d $funcname graid "$GRAID_DELETE" $disk
	f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" /dev/$disk

	# Make doubly-sure backup GPT is destroyed
	f_eval_catch -d $funcname gpart "$GPART_CREATE" gpt $disk
	f_eval_catch -d $funcname gpart "$GPART_DESTROY_F" $disk

	#
	# Lay down the desired type of partition scheme
	#
	local setsize mbrindex align_small align_big
	#
	# If user has requested 4 K alignment, add these params to the
	# gpart add calls. With GPT, we align large partitions to 1 M for
	# improved performance on SSDs. MBR does not always play well with gaps
	# between partitions, so all alignment is only 4k for that case.
	# With MBR, we align the BSD partition that contains the MBR, otherwise
	# the system fails to boot.
	#
	if [ "$ZFSBOOT_FORCE_4K_SECTORS" ]; then
		align_small="-a 4k"
		align_big="-a 1m"
	fi

	case "$ZFSBOOT_PARTITION_SCHEME" in
	""|GPT*) f_dprintf "$funcname: Creating GPT layout..."
		#
		# 1. Create GPT layout using labels
		#
		f_eval_catch $funcname gpart "$GPART_CREATE" gpt $disk ||
		             return $FAILURE

		#
		# Apply workarounds if requested by the user
		#
		if [ "$ZFSBOOT_PARTITION_SCHEME" = "GPT + Lenovo Fix" ]; then
			f_eval_catch $funcname gpart "$GPART_SET_LENOVOFIX" \
			             $disk || return $FAILURE
		elif [ "$ZFSBOOT_PARTITION_SCHEME" = "GPT + Active" ]; then
			f_eval_catch $funcname gpart "$GPART_SET_PMBR_ACTIVE" \
			             $disk || return $FAILURE
		fi

		#
		# 2. Add small freebsd-boot and/or efi partition
		#
		if [ "$ZFSBOOT_BOOT_TYPE" = "UEFI" -o "$ZFSBOOT_BOOT_TYPE" = "BIOS+UEFI" ]; then
			f_eval_catch $funcname gpart \
			             "$GPART_ADD_ALIGN_LABEL_WITH_SIZE" \
			             "$align_small" efiboot$index efi 200M \
				     $disk ||
			             return $FAILURE

			f_eval_catch $funcname mkdir "$MKDIR_P" \
				     "$BSDINSTALL_TMPETC/esp" || return $FAILURE
			f_eval_catch $funcname newfs_msdos "$NEWFS_ESP" "16" \
				     "EFISYS" "/dev/${disk}p1" ||
				     return $FAILURE
			f_eval_catch $funcname mount "$MOUNT_TYPE" "msdosfs" \
				     "/dev/${disk}p1" \
				     "$BSDINSTALL_TMPETC/esp" ||
				     return $FAILURE
			f_eval_catch $funcname mkdir "$MKDIR_P" \
				     "$BSDINSTALL_TMPETC/esp/efi/boot" ||
				     return $FAILURE
			f_eval_catch $funcname cp "$COPY" "/boot/loader.efi" \
				     "$BSDINSTALL_TMPETC/esp/efi/boot/$ZFSBOOT_ESP_NAME" ||
				     return $FAILURE
			f_eval_catch $funcname echo "$ECHO_OVERWRITE" \
				     "$ZFSBOOT_ESP_NAME" \
				     "$BSDINSTALL_TMPETC/esp/efi/boot/startup.nsh" ||
				     return $FAILURE
			f_eval_catch $funcname umount "$UMOUNT" \
				     "$BSDINSTALL_TMPETC/esp" ||
				     return $FAILURE
		fi

		if [ "$ZFSBOOT_BOOT_TYPE" = "BIOS" -o "$ZFSBOOT_BOOT_TYPE" = "BIOS+UEFI" ]; then
			f_eval_catch $funcname gpart \
			             "$GPART_ADD_ALIGN_LABEL_WITH_SIZE" \
			             "$align_small" gptboot$index freebsd-boot \
			             512k $disk || return $FAILURE
			if [ "$ZFSBOOT_BOOT_TYPE" = "BIOS" ]; then
				f_eval_catch $funcname gpart "$GPART_BOOTCODE_PART" \
				             /boot/pmbr /boot/gptzfsboot 1 $disk ||
				             return $FAILURE
			else
				f_eval_catch $funcname gpart "$GPART_BOOTCODE_PART" \
				             /boot/pmbr /boot/gptzfsboot 2 $disk ||
				             return $FAILURE
			fi
		fi

		# NB: zpool will use the `zfs#' GPT labels
		if [ "$ZFSBOOT_BOOT_TYPE" = "BIOS+UEFI" ]; then
			if [ "$ZFSBOOT_BOOT_POOL" ]; then
				bootpart=p3 swappart=p4 targetpart=p4
				[ ${swapsize:-0} -gt 0 ] && targetpart=p5
			else
				# Bootpart unused
				bootpart=p3 swappart=p3 targetpart=p3
				[ ${swapsize:-0} -gt 0 ] && targetpart=p4
			fi
		else
			if [ "$ZFSBOOT_BOOT_POOL" ]; then
				bootpart=p2 swappart=p3 targetpart=p3
				[ ${swapsize:-0} -gt 0 ] && targetpart=p4
			else
				# Bootpart unused
				bootpart=p2 swappart=p2 targetpart=p2
				[ ${swapsize:-0} -gt 0 ] && targetpart=p3
			fi
		fi

		#
		# Prepare boot pool if enabled (e.g., for geli(8))
		#
		if [ "$ZFSBOOT_BOOT_POOL" ]; then
			f_eval_catch $funcname gpart \
			             "$GPART_ADD_ALIGN_LABEL_WITH_SIZE" \
			             "$align_big" boot$index freebsd-zfs \
			             ${bootsize}b $disk ||
			             return $FAILURE
			# Pedantically nuke any old labels
			f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
			                /dev/$disk$bootpart
			if [ "$ZFSBOOT_GELI_ENCRYPTION" ]; then
				# Pedantically detach targetpart for later
				f_eval_catch -d $funcname geli \
				                "$GELI_DETACH_F" \
				                /dev/$disk$targetpart
			fi
		fi

		#
		# 3. Add freebsd-swap partition labeled `swap#'
		#
		if [ ${swapsize:-0} -gt 0 ]; then
			f_eval_catch $funcname gpart \
			             "$GPART_ADD_ALIGN_LABEL_WITH_SIZE" \
			             "$align_big" swap$index freebsd-swap \
			             ${swapsize}b $disk ||
			             return $FAILURE
			# Pedantically nuke any old labels on the swap
			f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
			                /dev/$disk$swappart
		fi

		#
		# 4. Add freebsd-zfs partition labeled `zfs#' for zroot
		#
		f_eval_catch $funcname gpart "$GPART_ADD_ALIGN_LABEL" \
		             "$align_big" zfs$index freebsd-zfs $disk ||
		             return $FAILURE
		f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
		                /dev/$disk$targetpart
		;;

	MBR) f_dprintf "$funcname: Creating MBR layout..."
		#
		# Enable boot pool if encryption is desired
		#
		[ "$ZFSBOOT_GELI_ENCRYPTION" ] && ZFSBOOT_BOOT_POOL=1
		#
		# 1. Create MBR layout (no labels)
		#
		f_eval_catch $funcname gpart "$GPART_CREATE" mbr $disk ||
		             return $FAILURE
		f_eval_catch $funcname gpart "$GPART_BOOTCODE" /boot/mbr \
		             $disk || return $FAILURE

		#
		# 2. Add freebsd slice with all available space
		#
		f_eval_catch $funcname gpart "$GPART_ADD_ALIGN" "$align_small" \
		             freebsd $disk ||
		             return $FAILURE
		f_eval_catch $funcname gpart "$GPART_SET_ACTIVE" 1 $disk ||
		             return $FAILURE
		# Pedantically nuke any old labels
		f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
		                /dev/${disk}s1
		# Pedantically nuke any old scheme
		f_eval_catch -d $funcname gpart "$GPART_DESTROY_F" ${disk}s1

		#
		# 3. Write BSD scheme to the freebsd slice
		#
		f_eval_catch $funcname gpart "$GPART_CREATE" BSD ${disk}s1 ||
		             return $FAILURE

		# NB: zpool will use s1a (no labels)
		bootpart=s1a swappart=s1b targetpart=s1d mbrindex=4

		#
		# Always prepare a boot pool on MBR
		# Do not align this partition, there must not be a gap
		#
		ZFSBOOT_BOOT_POOL=1
		f_eval_catch $funcname gpart \
		             "$GPART_ADD_ALIGN_INDEX_WITH_SIZE" \
		             "" 1 freebsd-zfs ${bootsize}b ${disk}s1 ||
		             return $FAILURE
		# Pedantically nuke any old labels
		f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
		                /dev/$disk$bootpart
		if [ "$ZFSBOOT_GELI_ENCRYPTION" ]; then
			# Pedantically detach targetpart for later
			f_eval_catch -d $funcname geli \
			                "$GELI_DETACH_F" \
					/dev/$disk$targetpart
		fi

		#
		# 4. Add freebsd-swap partition
		#
		if [ ${swapsize:-0} -gt 0 ]; then
			f_eval_catch $funcname gpart \
			             "$GPART_ADD_ALIGN_INDEX_WITH_SIZE" \
			             "$align_small" 2 freebsd-swap ${swapsize}b ${disk}s1 ||
			             return $FAILURE
			# Pedantically nuke any old labels on the swap
			f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
			                /dev/${disk}s1b
		fi

		#
		# 5. Add freebsd-zfs partition for zroot
		#
		f_eval_catch $funcname gpart "$GPART_ADD_ALIGN_INDEX" \
		             "$align_small" $mbrindex freebsd-zfs ${disk}s1 || return $FAILURE
		f_eval_catch -d $funcname zpool "$ZPOOL_LABELCLEAR_F" \
		                /dev/$disk$targetpart # Pedantic
		f_eval_catch $funcname dd "$DD_WITH_OPTIONS" \
		             /boot/zfsboot /dev/${disk}s1 count=1 ||
		             return $FAILURE
		;;

	esac # $ZFSBOOT_PARTITION_SCHEME

	# Update fstab(5)
	local swapsize
	f_expand_number "$ZFSBOOT_SWAP_SIZE" swapsize
	if [ "$isswapmirror" ]; then
		# This is not the first disk in the mirror, do nothing
	elif [ ${swapsize:-0} -eq 0 ]; then
		# If swap is 0 sized, don't add it to fstab
	elif [ "$ZFSBOOT_SWAP_ENCRYPTION" -a "$ZFSBOOT_SWAP_MIRROR" ]; then
		f_eval_catch $funcname printf "$PRINTF_FSTAB" \
		             /dev/mirror/swap.eli none swap sw 0 0 \
		             $BSDINSTALL_TMPETC/fstab ||
		             return $FAILURE
		isswapmirror=1
	elif [ "$ZFSBOOT_SWAP_MIRROR" ]; then
		f_eval_catch $funcname printf "$PRINTF_FSTAB" \
		             /dev/mirror/swap none swap sw 0 0 \
		             $BSDINSTALL_TMPETC/fstab ||
		             return $FAILURE
		isswapmirror=1
	elif [ "$ZFSBOOT_SWAP_ENCRYPTION" ]; then
		f_eval_catch $funcname printf "$PRINTF_FSTAB" \
		             /dev/$disk${swappart}.eli none swap sw 0 0 \
		             $BSDINSTALL_TMPETC/fstab ||
		             return $FAILURE
	else
		f_eval_catch $funcname printf "$PRINTF_FSTAB" \
		             /dev/$disk$swappart none swap sw 0 0 \
		             $BSDINSTALL_TMPETC/fstab ||
		             return $FAILURE
	fi

	return $SUCCESS
}

# zfs_create_boot $poolname $vdev_type $disks ...
#
# Creates boot pool and dataset layout. Returns error if something goes wrong.
# Errors are printed to stderr for collection and display.
#
zfs_create_boot()
{
	local funcname=zfs_create_boot
	local zroot_name="$1"
	local zroot_vdevtype="$2"
	local zroot_vdevs= # Calculated below
	local swap_devs= # Calculated below
	local boot_vdevs= # Used for geli(8) and/or MBR layouts
	shift 2 # poolname vdev_type
	local disks="$*" disk
	local isswapmirror
	local bootpart targetpart swappart # Set by zfs_create_diskpart() below
	local create_options

	#
	# Pedantic checks; should never be seen
	#
	if [ ! "$zroot_name" ]; then
		f_dprintf "$funcname: NULL poolname"
		msg_error="$msg_error: $funcname" \
			f_show_err "$msg_null_poolname"
		return $FAILURE
	fi
	if [ $# -lt 1 ]; then
		f_dprintf "$funcname: missing disk arguments"
		msg_error="$msg_error: $funcname" \
			f_show_err "$msg_missing_disk_arguments"
		return $FAILURE
	fi
	f_dprintf "$funcname: poolname=[%s] vdev_type=[%s]" \
	          "$zroot_name" "$zroot_vdevtype"

	#
	# Initialize fstab(5)
	#
	f_dprintf "$funcname: Initializing temporary fstab(5) file..."
	f_eval_catch $funcname sh "$SHELL_TRUNCATE" $BSDINSTALL_TMPETC/fstab ||
	             return $FAILURE
	f_eval_catch $funcname printf "$PRINTF_FSTAB" \
	             "# Device" Mountpoint FStype Options Dump "Pass#" \
	             $BSDINSTALL_TMPETC/fstab || return $FAILURE

	#
	# Expand SI units in desired sizes
	#
	f_dprintf "$funcname: Expanding supplied size values..."
	local swapsize bootsize
	if ! f_expand_number "$ZFSBOOT_SWAP_SIZE" swapsize; then
		f_dprintf "$funcname: Invalid swap size \`%s'" \
		          "$ZFSBOOT_SWAP_SIZE"
		f_show_err "$msg_invalid_swap_size" "$ZFSBOOT_SWAP_SIZE"
		return $FAILURE
	fi
	if ! f_expand_number "$ZFSBOOT_BOOT_POOL_SIZE" bootsize; then
		f_dprintf "$funcname: Invalid boot pool size \`%s'" \
		          "$ZFSBOOT_BOOT_POOL_SIZE"
		f_show_err "$msg_invalid_boot_pool_size" \
		           "$ZFSBOOT_BOOT_POOL_SIZE"
		return $FAILURE
	fi
	f_dprintf "$funcname: ZFSBOOT_SWAP_SIZE=[%s] swapsize=[%s]" \
	          "$ZFSBOOT_SWAP_SIZE" "$swapsize"
	f_dprintf "$funcname: ZFSBOOT_BOOT_POOL_SIZE=[%s] bootsize=[%s]" \
	          "$ZFSBOOT_BOOT_POOL_SIZE" "$bootsize"

	#
	# Destroy the pool in-case this is our second time 'round (case of
	# failure and installer presented ``Retry'' option to come back).
	#
	# NB: If we don't destroy the pool, later gpart(8) destroy commands
	# that try to clear existing partitions (see zfs_create_diskpart())
	# will fail with a `Device Busy' error, leading to `GEOM exists'.
	#
	f_eval_catch -d $funcname zpool "$ZPOOL_DESTROY" "$zroot_name"

	#
	# Prepare the disks and build pool device list(s)
	#
	f_dprintf "$funcname: Preparing disk partitions for ZFS pool..."

	# Force 4K sectors using vfs.zfs.min_auto_ashift=12
	if [ "$ZFSBOOT_FORCE_4K_SECTORS" ]; then
		f_dprintf "$funcname: With 4K sectors..."
		f_eval_catch $funcname sysctl "$SYSCTL_ZFS_MIN_ASHIFT_12" \
		    || return $FAILURE
		sysctl kern.geom.part.mbr.enforce_chs=0
	fi
	local n=0
	for disk in $disks; do
		zfs_create_diskpart $disk $n || return $FAILURE
		# Now $bootpart, $targetpart, and $swappart are set (suffix
		# for $disk)
		if [ "$ZFSBOOT_BOOT_POOL" ]; then
			boot_vdevs="$boot_vdevs $disk$bootpart"
		fi
		zroot_vdevs="$zroot_vdevs $disk$targetpart"
		if [ "$ZFSBOOT_GELI_ENCRYPTION" ]; then
			zroot_vdevs="$zroot_vdevs.eli"
		fi

		n=$(( $n + 1 ))
	done # disks

	#
	# If we need/want a boot pool, create it
	#
	if [ "$ZFSBOOT_BOOT_POOL" ]; then
		local bootpool_vdevtype= # Calculated below
		local bootpool_options= # Calculated below
		local bootpool_name="$ZFSBOOT_BOOT_POOL_NAME"
		local bootpool="$BSDINSTALL_CHROOT/$bootpool_name"
		local zroot_key="${ZFSBOOT_GELI_KEY_FILE#/}"

		f_dprintf "$funcname: Setting up boot pool..."
		[ "$ZFSBOOT_GELI_ENCRYPTION" ] &&
			f_dprintf "$funcname: For encrypted root disk..."

		# Create parent directory for boot pool
		f_eval_catch -d $funcname umount "$UMOUNT" /mnt
		f_eval_catch $funcname mount "$MOUNT_TYPE" tmpfs none \
		             $BSDINSTALL_CHROOT || return $FAILURE

		# Create mirror across the boot partition on all disks
		local nvdevs
		f_count nvdevs $boot_vdevs
		[ $nvdevs -gt 1 ] && bootpool_vdevtype=mirror

		create_options="$ZFSBOOT_BOOT_POOL_CREATE_OPTIONS"
		bootpool_options="-o altroot=$BSDINSTALL_CHROOT"
		bootpool_options="$bootpool_options $create_options"
		bootpool_options="$bootpool_options -m \"/$bootpool_name\" -f"
		f_eval_catch $funcname zpool "$ZPOOL_CREATE_WITH_OPTIONS" \
		             "$bootpool_options" "$bootpool_name" \
		             "$bootpool_vdevtype" "$boot_vdevs" ||
		             return $FAILURE

		f_eval_catch $funcname mkdir "$MKDIR_P" "$bootpool/boot" ||
		             return $FAILURE

		if [ "$ZFSBOOT_GELI_ENCRYPTION" ]; then
			# Generate an encryption key using random(4)
			f_eval_catch $funcname dd "$DD_WITH_OPTIONS" \
			             /dev/random "$bootpool/$zroot_key" \
			             "bs=4096 count=1" || return $FAILURE
			f_eval_catch $funcname chmod "$CHMOD_MODE" \
			             go-wrx "$bootpool/$zroot_key" ||
			             return $FAILURE
		fi

	fi

	#
	# Create the geli(8) GEOMS
	#
	if [ "$ZFSBOOT_GELI_ENCRYPTION" ]; then
		#
		# Load the AES-NI kernel module to accelerate encryption
		#
		f_eval_catch -d $funcname kldload "$KLDLOAD" "aesni"
		# Prompt user for password (twice)
		if ! msg_enter_new_password="$msg_geli_password" \
			f_dialog_input_password
		then
			f_dprintf "$funcname: User cancelled"
			f_show_err "$msg_user_cancelled"
			return $FAILURE
		fi

		# Initialize geli(8) on each of the target partitions
		for disk in $disks; do
			f_dialog_info "$msg_geli_setup" \
				2>&1 >&$DIALOG_TERMINAL_PASSTHRU_FD
			if [ "$ZFSBOOT_BOOT_POOL" ]; then
				if ! echo "$pw_password" | f_eval_catch \
					$funcname geli "$GELI_PASSWORD_INIT" \
					"$bootpool/boot/$disk$targetpart.eli" \
					AES-XTS "$bootpool/$zroot_key" \
					$disk$targetpart
				then
					f_interactive || f_die
					unset pw_password # Sensitive info
					return $FAILURE
				fi
				if ! echo "$pw_password" | f_eval_catch \
					$funcname geli "$GELI_ATTACH" \
					"$bootpool/$zroot_key" $disk$targetpart
				then
					f_interactive || f_die
					unset pw_password # Sensitive info
					return $FAILURE
				fi
			else
				# With no bootpool, there is no place to store
				# the key files, use only a password
				if ! echo "$pw_password" | f_eval_catch \
					$funcname geli \
					"$GELI_PASSWORD_GELIBOOT_INIT" AES-XTS \
					$disk$targetpart
				then
					f_interactive || f_die
					unset pw_password # Sensitive info
					return $FAILURE
				fi
				if ! echo "$pw_password" | f_eval_catch \
					$funcname geli "$GELI_ATTACH_NOKEY" \
					$disk$targetpart
				then
					f_interactive || f_die
					unset pw_password # Sensitive info
					return $FAILURE
				fi
			fi
		done
		unset pw_password # Sensitive info
	fi

	if [ "$ZFSBOOT_BOOT_POOL" ]; then
		# Clean up
		f_eval_catch $funcname zfs "$ZFS_UNMOUNT" "$bootpool_name" ||
			return $FAILURE
		f_eval_catch -d $funcname umount "$UMOUNT" /mnt # tmpfs
	fi

	#
	# Create the gmirror(8) GEOMS for swap
	#
	if [ ${swapsize:-0} -gt 0 -a "$ZFSBOOT_SWAP_MIRROR" ]; then
		for disk in $disks; do
			swap_devs="$swap_devs $disk$swappart"
		done
		f_eval_catch $funcname gmirror "$SWAP_GMIRROR_LABEL" \
			"$swap_devs" || return $FAILURE
	fi

	#
	# Create the ZFS root pool with desired type and disk devices
	#
	f_dprintf "$funcname: Creating root pool..."
	create_options="$ZFSBOOT_POOL_CREATE_OPTIONS"
	if [ "$zroot_vdevtype" == "raid10" ]; then
		raid10_vdevs=""
		for vdev in $zroot_vdevs; do
			f_count nvdev $raid10_vdevs
			if [ $(( $nvdev % 3 )) -eq 0 ]; then
				raid10_vdevs="$raid10_vdevs mirror"
			fi
			raid10_vdevs="$raid10_vdevs $vdev"
		done
		f_eval_catch $funcname zpool "$ZPOOL_CREATE_WITH_OPTIONS" \
			"-o altroot=$BSDINSTALL_CHROOT $create_options -m none -f" \
			"$zroot_name" "" "$raid10_vdevs" ||
			return $FAILURE
	else
		f_eval_catch $funcname zpool "$ZPOOL_CREATE_WITH_OPTIONS" \
			"-o altroot=$BSDINSTALL_CHROOT $create_options -m none -f" \
			"$zroot_name" "$zroot_vdevtype" "$zroot_vdevs" ||
			return $FAILURE
	fi

	#
	# Create ZFS dataset layout within the new root pool
	#
	f_dprintf "$funcname: Creating ZFS datasets..."
	echo "$ZFSBOOT_DATASETS" | while read dataset options; do
		# Skip blank lines and comments
		case "$dataset" in "#"*|"") continue; esac
		# Remove potential inline comments in options
		options="${options%%#*}"
		# Replace tabs with spaces
		f_replaceall "$options" "	" " " options
		# Reduce contiguous runs of space to one single space
		oldoptions=
		while [ "$oldoptions" != "$options" ]; do
			oldoptions="$options"
			f_replaceall "$options" "  " " " options
		done
		# Replace both commas and spaces with ` -o '
		f_replaceall "$options" "[ ,]" " -o " options
		# Create the dataset with desired options
		f_eval_catch $funcname zfs "$ZFS_CREATE_WITH_OPTIONS" \
		             "${options:+-o $options}" "$zroot_name$dataset" ||
		             return $FAILURE
	done

	#
	# Set a mountpoint for the root of the pool so newly created datasets
	# have a mountpoint to inherit
	#
	f_dprintf "$funcname: Setting mountpoint for root of the pool..."
	f_eval_catch $funcname zfs "$ZFS_SET" \
		"mountpoint=/$zroot_name" "$zroot_name" ||
		return $FAILURE

	# Touch up permissions on the tmp directories
	f_dprintf "$funcname: Modifying directory permissions..."
	local dir
	for dir in /tmp /var/tmp; do
		f_eval_catch $funcname mkdir "$MKDIR_P" \
		             $BSDINSTALL_CHROOT$dir || return $FAILURE
		f_eval_catch $funcname chmod "$CHMOD_MODE" 1777 \
		             $BSDINSTALL_CHROOT$dir || return $FAILURE
	done

	# Set bootfs property
	local zroot_bootfs="$ZFSBOOT_BEROOT_NAME/$ZFSBOOT_BOOTFS_NAME"
	f_dprintf "$funcname: Setting bootfs property..."
	f_eval_catch $funcname zpool "$ZPOOL_SET" \
		"bootfs=\"$zroot_name/$zroot_bootfs\"" "$zroot_name" ||
		return $FAILURE

	# MBR boot loader touch-up
	if [ "$ZFSBOOT_PARTITION_SCHEME" = "MBR" ]; then
		# Export the pool(s)
		f_dprintf "$funcname: Temporarily exporting ZFS pool(s)..."
		f_eval_catch $funcname zpool "$ZPOOL_EXPORT" "$zroot_name" ||
			     return $FAILURE
		if [ "$ZFSBOOT_BOOT_POOL" ]; then
			f_eval_catch $funcname zpool "$ZPOOL_EXPORT" \
				     "$bootpool_name" || return $FAILURE
		fi

		f_dprintf "$funcname: Updating MBR boot loader on disks..."
		# Stick the ZFS boot loader in the "convenient hole" after
		# the ZFS internal metadata
		for disk in $disks; do
			f_eval_catch $funcname dd "$DD_WITH_OPTIONS" \
			             /boot/zfsboot /dev/$disk$bootpart \
			             "skip=1 seek=1024" || return $FAILURE
		done

		# Re-import the ZFS pool(s)
		f_dprintf "$funcname: Re-importing ZFS pool(s)..."
		f_eval_catch $funcname zpool "$ZPOOL_IMPORT_WITH_OPTIONS" \
			     "-o altroot=\"$BSDINSTALL_CHROOT\"" "$zroot_name" ||
			     return $FAILURE
		if [ "$ZFSBOOT_BOOT_POOL" ]; then
			# Import the bootpool, but do not mount it yet
			f_eval_catch $funcname zpool "$ZPOOL_IMPORT_WITH_OPTIONS" \
				     "-o altroot=\"$BSDINSTALL_CHROOT\" -N" \
				     "$bootpool_name" || return $FAILURE
		fi
	fi

	# Remount bootpool and create symlink(s)
	if [ "$ZFSBOOT_BOOT_POOL" ]; then
		f_eval_catch $funcname zfs "$ZFS_MOUNT" "$bootpool_name" ||
			return $FAILURE
		f_dprintf "$funcname: Creating /boot symlink for boot pool..."
		f_eval_catch $funcname ln "$LN_SF" "$bootpool_name/boot" \
		             $BSDINSTALL_CHROOT/boot || return $FAILURE
	fi

	# zpool.cache is required to mount more than one pool at boot time
	f_dprintf "$funcname: Configuring zpool.cache for zroot..."
	f_eval_catch $funcname mkdir "$MKDIR_P" $BSDINSTALL_CHROOT/boot/zfs ||
	             return $FAILURE
	f_eval_catch $funcname zpool "$ZPOOL_SET" \
	             "cachefile=\"$BSDINSTALL_CHROOT/boot/zfs/zpool.cache\"" \
	             "$zroot_name" || return $FAILURE

	if [ "$ZFSBOOT_BOOT_POOL" ]; then
		f_eval_catch $funcname printf "$PRINTF_CONF" \
			vfs.root.mountfrom "\"zfs:$zroot_name/$zroot_bootfs\"" \
			$BSDINSTALL_TMPBOOT/loader.conf.root || return $FAILURE
	fi
	#
	# Set canmount=noauto so that the default Boot Environment (BE) does not
	# get mounted if a different BE is selected from the beastie menu
	#
	f_dprintf "$funcname: Set canmount=noauto for the root of the pool..."
	f_eval_catch $funcname zfs "$ZFS_SET" "canmount=noauto" \
		"$zroot_name/$ZFSBOOT_BEROOT_NAME/$ZFSBOOT_BOOTFS_NAME"

	# Last, but not least... required lines for rc.conf(5)/loader.conf(5)
	# NOTE: We later concatenate these into their destination
	f_dprintf "%s: Configuring rc.conf(5)/loader.conf(5) additions..." \
	          "$funcname"
	f_eval_catch $funcname echo "$ECHO_APPEND" 'zfs_enable=\"YES\"' \
	             $BSDINSTALL_TMPETC/rc.conf.zfs || return $FAILURE
	f_eval_catch $funcname echo "$ECHO_APPEND" \
	             'kern.geom.label.disk_ident.enable=\"0\"' \
	             $BSDINSTALL_TMPBOOT/loader.conf.zfs || return $FAILURE
	f_eval_catch $funcname echo "$ECHO_APPEND" \
	             'kern.geom.label.gptid.enable=\"0\"' \
	             $BSDINSTALL_TMPBOOT/loader.conf.zfs || return $FAILURE

	if [ "$ZFSBOOT_FORCE_4K_SECTORS" ]; then
		f_eval_catch $funcname echo "$ECHO_APPEND" \
	             'vfs.zfs.min_auto_ashift=12' \
	             $BSDINSTALL_TMPETC/sysctl.conf.zfs || return $FAILURE
	fi

	if [ "$ZFSBOOT_SWAP_MIRROR" ]; then
		f_eval_catch $funcname echo "$ECHO_APPEND" \
		             'geom_mirror_load=\"YES\"' \
		             $BSDINSTALL_TMPBOOT/loader.conf.gmirror ||
		             return $FAILURE
	fi

	# We're all done unless we should go on to do encryption
	[ "$ZFSBOOT_GELI_ENCRYPTION" ] || return $SUCCESS

	#
	# Configure geli(8)-based encryption
	#
	f_dprintf "$funcname: Configuring disk encryption..."
	f_eval_catch $funcname echo "$ECHO_APPEND" 'aesni_load=\"YES\"' \
		$BSDINSTALL_TMPBOOT/loader.conf.aesni || return $FAILURE
	f_eval_catch $funcname echo "$ECHO_APPEND" 'geom_eli_load=\"YES\"' \
		$BSDINSTALL_TMPBOOT/loader.conf.geli || return $FAILURE

	# We're all done unless we should go on for boot pool
	[ "$ZFSBOOT_BOOT_POOL" ] || return $SUCCESS

	for disk in $disks; do
		f_eval_catch $funcname printf "$PRINTF_CONF" \
			geli_%s_keyfile0_load "$disk$targetpart YES" \
			$BSDINSTALL_TMPBOOT/loader.conf.$disk$targetpart ||
			return $FAILURE
		f_eval_catch $funcname printf "$PRINTF_CONF" \
			geli_%s_keyfile0_type \
			"$disk$targetpart $disk$targetpart:geli_keyfile0" \
			$BSDINSTALL_TMPBOOT/loader.conf.$disk$targetpart ||
			return $FAILURE
		f_eval_catch $funcname printf "$PRINTF_CONF" \
			geli_%s_keyfile0_name \
			"$disk$targetpart \"$ZFSBOOT_GELI_KEY_FILE\"" \
			$BSDINSTALL_TMPBOOT/loader.conf.$disk$targetpart ||
			return $FAILURE
	done

	# Set cachefile for boot pool so it auto-imports at system start
	f_dprintf "$funcname: Configuring zpool.cache for boot pool..."
	f_eval_catch $funcname zpool "$ZPOOL_SET" \
	             "cachefile=\"$BSDINSTALL_CHROOT/boot/zfs/zpool.cache\"" \
	             "$bootpool_name" || return $FAILURE

	# Some additional geli(8) requirements for loader.conf(5)
	for option in \
		'zpool_cache_load=\"YES\"' \
		'zpool_cache_type=\"/boot/zfs/zpool.cache\"' \
		'zpool_cache_name=\"/boot/zfs/zpool.cache\"' \
		'geom_eli_passphrase_prompt=\"YES\"' \
	; do
		f_eval_catch $funcname echo "$ECHO_APPEND" "$option" \
		             $BSDINSTALL_TMPBOOT/loader.conf.zfs ||
		             return $FAILURE
	done
	return $SUCCESS
}

# dialog_menu_diskinfo
#
# Prompt the user to select a disk and then provide detailed info on it.
#
dialog_menu_diskinfo()
{
	local device disk

	#
	# Break from loop when user cancels disk selection
	#
	while :; do
		device=$( msg_cancel="$msg_back" f_device_menu \
			"$DIALOG_TITLE" "$msg_select_a_disk_device" "" \
			$DEVICE_TYPE_DISK 2>&1 ) || break
		$device get name disk

		# Show gpart(8) `show' and camcontrol(8) `inquiry' data
		f_show_msg "$msg_detailed_disk_info" \
			"$disk" "$( gpart show $disk 2> /dev/null )" \
			"$disk" "$( camcontrol inquiry $disk 2> /dev/null )" \
			"$disk" "$( camcontrol identify $disk 2> /dev/null )"
	done

	return $SUCCESS
}

############################################################ MAIN

#
# Initialize
#
f_dialog_title "$msg_zfs_configuration"
f_dialog_backtitle "$msg_freebsd_installer"

# User may have specifically requested ZFS-related operations be interactive
! f_interactive && f_zfsinteractive && unset $VAR_NONINTERACTIVE

#
# Debugging
#
f_dprintf "BSDINSTALL_CHROOT=[%s]" "$BSDINSTALL_CHROOT"
f_dprintf "BSDINSTALL_TMPETC=[%s]" "$BSDINSTALL_TMPETC"
f_dprintf "FSTAB_FMT=[%s]" "$FSTAB_FMT"

#
# Determine default boot type
#
case $(uname -m) in
arm64)
	# We support only UEFI boot for arm64
	: ${ZFSBOOT_BOOT_TYPE:=UEFI}
	: ${ZFSBOOT_PARTITION_SCHEME:=GPT}
	;;
*)
	# We use BIOS+UEFI for maximum compatibility
	: ${ZFSBOOT_BOOT_TYPE:=BIOS+UEFI}
	: ${ZFSBOOT_PARTITION_SCHEME:=GPT}
	;;
esac

#
# The EFI loader installed in the ESP (EFI System Partition) must
# have the expected name in order to load correctly.
#
[ "$ZFSBOOT_ESP_NAME" ] || case "${UNAME_m:-$( uname -m )}" in
	arm64) ZFSBOOT_ESP_NAME=BOOTaa64.efi ;;
	arm) ZFSBOOT_ESP_NAME=BOOTarm.efi ;;
	i386) ZFSBOOT_ESP_NAME=BOOTia32.efi ;;
	amd64) ZFSBOOT_ESP_NAME=BOOTx64.efi ;;
	*)
		f_dprintf "Unsupported architecture: %s" $UNAME_m
		f_die
esac

#
# Loop over the main menu until we've accomplished what we came here to do
#
while :; do
	if ! f_interactive; then
		retval=$DIALOG_OK
		mtag=">>> $msg_install"
	else
		retval=$DIALOG_OK
		mtag=">>> $msg_install"
		#dialog_menu_main
		#retval=$?
		#f_dialog_menutag_fetch mtag
	fi

	f_dprintf "retval=%u mtag=[%s]" $retval "$mtag"
	[ $retval -eq $DIALOG_OK ] || f_die

	case "$mtag" in
	">>> $msg_install")
		#
		# First, validate the user's selections
		#

		# Make sure they gave us a name for the pool
		if [ ! "$ZFSBOOT_POOL_NAME" ]; then
			f_dprintf "Pool name cannot be empty."
			f_show_err "$msg_pool_name_cannot_be_empty"
			continue
		fi

		# Validate vdev type against number of disks selected/scripted
		# (also validates that ZFSBOOT_DISKS are real [probed] disks)
		# NB: dialog_menu_layout supports running non-interactively
		dialog_menu_layout || return $FAILURE

		# Make sure each disk will have room for ZFS
		if f_expand_number "$ZFSBOOT_SWAP_SIZE" swapsize &&
		   f_expand_number "$ZFSBOOT_BOOT_POOL_SIZE" bootsize &&
		   f_expand_number "1g" zpoolmin
		then
			minsize=$(( $swapsize + $zpoolmin )) teeny_disks=
			[ "$ZFSBOOT_BOOT_POOL" ] &&
				minsize=$(( $minsize + $bootsize ))
			for disk in $ZFSBOOT_DISKS; do
				debug= f_device_find -1 \
					$disk $DEVICE_TYPE_DISK device
				$device get capacity disksize || continue
				[ ${disksize:-0} -ge 0 ] || disksize=0
				[ $disksize -lt $minsize ] &&
					teeny_disks="$teeny_disks $disk"
			done
			if [ "$teeny_disks" ]; then
				f_dprintf "swapsize=[%s] bootsize[%s] %s" \
				          "$ZFSBOOT_SWAP_SIZE" \
				          "$ZFSBOOT_BOOT_POOL_SIZE" \
				          "minsize=[$minsize]"
				f_dprintf "These disks are too small: %s" \
				          "$teeny_disks"
				f_show_err "$msg_these_disks_are_too_small" \
				           "$ZFSBOOT_SWAP_SIZE" \
				           "$ZFSBOOT_BOOT_POOL_SIZE" \
				           "$teeny_disks"
				continue
			fi
		fi

		#
		# Last Chance!
		#
		if f_interactive; then
			dialog_last_chance $ZFSBOOT_DISKS || continue
		fi

		#
		# Let's do this
		#

		vdev_type="$ZFSBOOT_VDEV_TYPE"

		# Blank the vdev type for the default layout
		[ "$vdev_type" = "stripe" ] && vdev_type=

		zfs_create_boot "$ZFSBOOT_POOL_NAME" \
		                "$vdev_type" $ZFSBOOT_DISKS || continue

		break # to success
		;;
	?" $msg_pool_type_disks")
		ZFSBOOT_CONFIRM_LAYOUT=1
		dialog_menu_layout
		# User has poked settings, disable later confirmation
		ZFSBOOT_CONFIRM_LAYOUT=
		;;
	"- $msg_rescan_devices") f_device_rescan ;;
	"- $msg_disk_info") dialog_menu_diskinfo ;;
	?" $msg_pool_name")
		# Prompt the user to input/change the name for the new pool
		f_dialog_input input \
			"$msg_please_enter_a_name_for_your_zpool" \
			"$ZFSBOOT_POOL_NAME" &&
			ZFSBOOT_POOL_NAME="$input"
		;;
	?" $msg_force_4k_sectors")
		# Toggle the variable referenced both by the menu and later
		if [ "$ZFSBOOT_FORCE_4K_SECTORS" ]; then
			ZFSBOOT_FORCE_4K_SECTORS=
		else
			ZFSBOOT_FORCE_4K_SECTORS=1
		fi
		;;
	?" $msg_encrypt_disks")
		# Toggle the variable referenced both by the menu and later
		if [ "$ZFSBOOT_GELI_ENCRYPTION" ]; then
			ZFSBOOT_GELI_ENCRYPTION=
		else
			ZFSBOOT_FORCE_4K_SECTORS=1
			ZFSBOOT_GELI_ENCRYPTION=1
		fi
		;;
	?" $msg_partition_scheme")
		# Toggle between GPT (BIOS), GPT (UEFI) and MBR
		if [ "$ZFSBOOT_PARTITION_SCHEME" = "GPT" -a "$ZFSBOOT_BOOT_TYPE" = "BIOS" ]; then
			ZFSBOOT_PARTITION_SCHEME="GPT"
			ZFSBOOT_BOOT_TYPE="UEFI"
		elif [ "$ZFSBOOT_PARTITION_SCHEME" = "GPT" -a "$ZFSBOOT_BOOT_TYPE" = "UEFI" ]; then
			ZFSBOOT_PARTITION_SCHEME="GPT"
			ZFSBOOT_BOOT_TYPE="BIOS+UEFI"
		elif [ "$ZFSBOOT_PARTITION_SCHEME" = "GPT" ]; then
			ZFSBOOT_PARTITION_SCHEME="MBR"
			ZFSBOOT_BOOT_TYPE="BIOS"
		elif [ "$ZFSBOOT_PARTITION_SCHEME" = "MBR" ]; then
			ZFSBOOT_PARTITION_SCHEME="GPT + Active"
			ZFSBOOT_BOOT_TYPE="BIOS"
		elif [ "$ZFSBOOT_PARTITION_SCHEME" = "GPT + Active" ]; then
			ZFSBOOT_PARTITION_SCHEME="GPT + Lenovo Fix"
			ZFSBOOT_BOOT_TYPE="BIOS"
		else
			ZFSBOOT_PARTITION_SCHEME="GPT"
			ZFSBOOT_BOOT_TYPE="BIOS"
		fi
		;;
	?" $msg_swap_size")
		# Prompt the user to input/change the swap size for each disk
		while :; do
		    f_dialog_input input \
			    "$msg_please_enter_amount_of_swap_space" \
			    "$ZFSBOOT_SWAP_SIZE" &&
			    ZFSBOOT_SWAP_SIZE="${input:-0}"
		    if f_expand_number "$ZFSBOOT_SWAP_SIZE" swapsize
		    then
			if [ $swapsize -ne 0 -a $swapsize -lt 104857600 ]; then
			    f_show_err "$msg_swap_toosmall" \
				       "$ZFSBOOT_SWAP_SIZE"
			    continue;
			else
			    break;
			fi
		    else
			f_show_err "$msg_swap_invalid" \
				   "$ZFSBOOT_SWAP_SIZE"
			continue;
		    fi
		done
		;;
	?" $msg_swap_mirror")
		# Toggle the variable referenced both by the menu and later
		if [ "$ZFSBOOT_SWAP_MIRROR" ]; then
			ZFSBOOT_SWAP_MIRROR=
		else
			ZFSBOOT_SWAP_MIRROR=1
		fi
		;;
	?" $msg_swap_encrypt")
		# Toggle the variable referenced both by the menu and later
		if [ "$ZFSBOOT_SWAP_ENCRYPTION" ]; then
			ZFSBOOT_SWAP_ENCRYPTION=
		else
			ZFSBOOT_SWAP_ENCRYPTION=1
		fi
		;;
	esac
done

exit $SUCCESS

################################################################################
# END
################################################################################
