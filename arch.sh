#!/usr/bin/env bash


echo -ne "
------------------------------------
   █████╗ ██████╗  ██████╗██╗  ██╗
  ██╔══██╗██╔══██╗██╔════╝██║  ██║
  ███████║██████╔╝██║     ███████║
  ██╔══██║██╔══██╗██║     ██╔══██║
  ██║  ██║██║  ██║╚██████╗██║  ██║
  ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
------------------------------------
"



# simple arch installer
set +a

if [ "$EUID" -ne 0 ]; then
   echo "Please run as root"
   exit
fi

# set start program time
readonly PROGSTARTTIME="$(date)"


KEYMAP=it
CONSOLEFONT=ter-u24n
DISK=/dev/sda
LUKS_PASSWORD=qaqa
SCRIPT_DIR="$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"


# INSTALL ARCH WITH LUKS AND BTRFS

# set root pwd before start
# passwd
# ip a
# connect ssh

function set_keymap(){
    loadkeys $KEYMAP
    setfont $CONSOLEFONT
}


# part table gpt
# create one partition EFI 512M /boot/efi
# create one partition ext2 1G /boot
# all the free space to linux filesystem for btrfs volumes
function partitioning(){
    sgdisk -Z /dev/sda
    sgdisk -a 2048 -o /dev/sda
    sgdisk -n 1::+1M --typecode=1:ef02 --change-name=1:'BIOSBOOT' ${DISK} # partition 1 (BIOS Boot Partition)
    sgdisk -n 2::+512M --typecode=2:ef00 --change-name=2:'EFIBOOT' ${DISK} # partition 2 (UEFI Boot Partition)
    sgdisk -n 3::-0 --typecode=3:8300 --change-name=3:'ROOT' ${DISK} # partition 3 (Root), default start, remaining
    if [[ ! -d "/sys/firmware/efi" ]]; then # Checking for bios system
        sgdisk -A 1:set:2 ${DISK}
    fi
    partprobe ${DISK} # reread partition table to ensure it is correct
    sgdisk -p ${DISK}

}


function filesystems(){

    if [[ "${DISK}" =~ "nvme" ]]; then
        partition2=${DISK}p2
        partition3=${DISK}p3
    else
        partition2=${DISK}2
        partition3=${DISK}3
    fi


    dd if=/dev/zero of=${partition2} bs=1M count=1
    dd if=/dev/zero of=${partition3} bs=1M count=1

    mkfs.vfat -F32 -n "EFIBOOT" ${partition2}
    # enter luks password to cryptsetup and format root partition
    echo -n "${LUKS_PASSWORD}" | cryptsetup -q --label ARCH_LUKS -v luksFormat ${partition3} -d -
    # open luks container and ROOT will be place holder
    echo -n "${LUKS_PASSWORD}" | cryptsetup open ${partition3} cryptroot -
    # now format that container
    mkfs.btrfs -f -L ARCH /dev/mapper/cryptroot
}



function subvolumes(){
    mount -o rw,noatime,space_cache=v2,ssd,discard=async,compress=lzo  /dev/mapper/cryptroot /mnt
    cd /mnt
    btrfs subvolume create @
    btrfs subvolume create @home
    btrfs subvolume create @snapshots
    btrfs subvolume create @var
    btrfs subvolume create @tmp
    cd /
    umount -R /mnt
}


function mount_filesystem(){

    mount -o rw,noatime,space_cache=v2,ssd,discard=async,compress=lzo,subvol=@ /dev/mapper/cryptroot /mnt
    mount --mkdir -o rw,noatime,space_cache=v2,ssd,discard=async,compress=lzo,subvol=@home /dev/mapper/cryptroot /mnt/home
    mount --mkdir -o rw,noatime,space_cache=v2,ssd,discard=async,compress=lzo,subvol=@var /dev/mapper/cryptroot /mnt/var
    mount --mkdir -o rw,noatime,space_cache=v2,ssd,discard=async,compress=lzo,subvol=@tmp /dev/mapper/cryptroot /mnt/tmp
    mount --mkdir -o rw,noatime,space_cache=v2,ssd,discard=async,compress=lzo,subvol=@snapshots /dev/mapper/cryptroot /mnt/snapshots

    mount --mkdir -t vfat -L EFIBOOT /mnt/boot
    mkdir -p /mnt/boot/efi
}


echo -ne "
-------------------------------------------------------------------------
                    Set Keymap $KEYMAP / Consolefont $CONSOLEFONT
-------------------------------------------------------------------------
"

set_keymap

echo -ne "
-------------------------------------------------------------------------
                    partitioning
-------------------------------------------------------------------------
"

partitioning


echo -ne "
-------------------------------------------------------------------------
                    Create filesystems
-------------------------------------------------------------------------
"

filesystems

echo -ne "
-------------------------------------------------------------------------
                    Create subvolumes
-------------------------------------------------------------------------
"

subvolumes

echo -ne "
-------------------------------------------------------------------------
                    Mount filesystem
-------------------------------------------------------------------------
"

mount_filesystem

echo -ne "
-------------------------------------------------------------------------
                    INSTALL BASE SYSTEM
-------------------------------------------------------------------------
"

pacstrap /mnt base linux linux-firmware btrfs-progs networkmanager vim man-db man-pages ntp grub efibootmgr base-devel wget archlinux-keyring --noconfirm --needed

cp -R ${SCRIPT_DIR}/arch_chroot.sh /mnt/root/

genfstab -pU /mnt > /mnt/etc/fstab
echo "
  Generated /etc/fstab:
"
cat /mnt/etc/fstab

echo -ne "
-------------------------------------------------------------------------
                    GRUB BIOS Bootloader Install & Check
-------------------------------------------------------------------------
"

if [[ ! -d "/sys/firmware/efi" ]]; then
    grub-install --boot-directory=/mnt/boot ${DISK}
else
    pacstrap /mnt efibootmgr --noconfirm --needed
fi


echo -ne "
-------------------------------------------------------------------------
                    SETUP IN CHROOT
-------------------------------------------------------------------------
"

arch-chroot /mnt /root/arch_chroot.sh


umount -R /mnt
cryptsetup close /dev/mapper/cryptroot
reboot

exit
