#!/bin/bash


TIMEZONE="Europe/Rome"
KEYMAP="it"
NAME_OF_MACHINE=ZOPPO

set -a

echo -ne "
-------------------------------------------------------------------------
                    Setting Locales
-------------------------------------------------------------------------
"

echo $NAME_OF_MACHINE > /etc/hostname


echo -ne "
127.0.0.1        localhost
::1              localhost
127.0.1.1        $NAME_OF_MACHINE
" > /etc/hosts

sed -i 's/#en_US.UTF-8/en_US.UTF-8/g' /etc/locale.gen
sed -i 's/#it_IT.UTF-8/it_IT.UTF-8/g' /etc/locale.gen
locale-gen


ln -sf /usr/share/zoneinfo/${TIMEZONE} /etc/localtime

echo LANG=it_IT.UTF-8 > /etc/locale.conf
echo KEYMAP=${KEYMAP} > /etc/vconsole.conf

hwclock --systohc --utc

echo -ne "
-------------------------------------------------------------------------
                    Setting Sudoers
-------------------------------------------------------------------------
"
# Add sudo no password rights
sed -i 's/^# %wheel ALL=(ALL) NOPASSWD: ALL/%wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/%wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers


#Add parallel downloading
sed -i 's/^#ParallelDownloads/ParallelDownloads/' /etc/pacman.conf

#Enable multilib
sed -i "/\[multilib\]/,/Include/"'s/^#//' /etc/pacman.conf
pacman -Sy --noconfirm


echo -ne "
-------------------------------------------------------------------------
                    Installing Microcode
-------------------------------------------------------------------------
"

# determine processor type and install microcode
proc_type=$(lscpu)
if grep -E "GenuineIntel" <<< ${proc_type}; then
    echo "Installing Intel microcode"
    pacman -S --noconfirm --needed intel-ucode
    # proc_ucode=intel-ucode.img
elif grep -E "AuthenticAMD" <<< ${proc_type}; then
    echo "Installing AMD microcode"
    pacman -S --noconfirm --needed amd-ucode
    # proc_ucode=amd-ucode.img
fi


echo -ne "
-------------------------------------------------------------------------
            User
-------------------------------------------------------------------------
"
useradd -m -G wheel wdog

# use chpasswd to enter $USERNAME:$password
echo "wdog:wdog" | chpasswd -s BCRYPT -c SHA512
echo "wdog password set"

echo "root:root" | chpasswd -s BCRYPT -c SHA512
echo "root password set"


echo -ne "
-------------------------------------------------------------------------
            BOOT
-------------------------------------------------------------------------
"

# making mkinitcpio with linux kernel
sed -i 's/HOOKS=(.*)//g' /etc/mkinitcpio.conf
echo "HOOKS=(base udev autodetect modconf kms block keymap encrypt filesystems keyboard fsck shutdown)" >> /etc/mkinitcpio.conf

mkinitcpio -p linux

if [[ -d "/sys/firmware/efi" ]]; then
    grub-install --efi-directory=/boot ${DISK}
fi

sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cryptdevice=\/dev\/sda3:cryptroot"/g' /etc/default/grub
echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub

grub-mkconfig -o /boot/grub/grub.cfg

echo -ne "
-------------------------------------------------------------------------
                    Cleaning
-------------------------------------------------------------------------
"
# Remove no password sudo rights
sed -i 's/^%wheel ALL=(ALL) NOPASSWD: ALL/# %wheel ALL=(ALL) NOPASSWD: ALL/' /etc/sudoers
sed -i 's/^%wheel ALL=(ALL:ALL) NOPASSWD: ALL/# %wheel ALL=(ALL:ALL) NOPASSWD: ALL/' /etc/sudoers
# Add sudo rights
sed -i 's/^# %wheel ALL=(ALL) ALL/%wheel ALL=(ALL) ALL/' /etc/sudoers
sed -i 's/^# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers



echo -ne "
-------------------------------------------------------------------------
                    Installing Packages
-------------------------------------------------------------------------
"

# Graphics Drivers find and install
# gpu_type=$(lspci)
# if grep -E "NVIDIA|GeForce" <<< ${gpu_type}; then
#     pacman -S --noconfirm --needed nvidia
# 	nvidia-xconfig
# elif lspci | grep 'VGA' | grep -E "Radeon|AMD"; then
#     pacman -S --noconfirm --needed xf86-video-amdgpu
# elif grep -E "Integrated Graphics Controller" <<< ${gpu_type}; then
#     pacman -S --noconfirm --needed libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
# elif grep -E "Intel Corporation UHD" <<< ${gpu_type}; then
#     pacman -S --needed --noconfirm libva-intel-driver libvdpau-va-gl lib32-vulkan-intel vulkan-intel libva-intel-driver libva-utils lib32-mesa
# fi



pacman -Sy --noconfirm networkmanager
pacman -Sy --noconfirm pacman-contrib reflector sudo
pacman -Sy --noconfirm gnome-desktop gdm gnome-extra alacritty nautilus gnome-tweaks gnome-shell gnome-shell-extensions pipewire pipewire-pulse pipewire-alsa wireplumber gnome-bluetooth
pacman -Sy --noconfirm firefox fish gnome-power-manager

# pacman -S --noconfirm sudo pacman-contrib archlinux-contrib reflector mesa pipewire pipewire-alsa \
#     pipewire-pulse pipewire-jack wireplumber firewalld noto-fonts git alacritty htop curl

systemctl enable -f fstrim.timer
systemctl enable -f paccache.timer
systemctl enable -f reflector.timer
systemctl enable -f bluetooth
systemctl enable -f NetworkManager
systemctl enable -f gdm.service


rm -rf /root/*.sh

echo -e "All set!"
