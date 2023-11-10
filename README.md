# arch_install
super easy and fast ARCH Linux installation with LUKS and BTRFS 


## install

- get ip of the new installation or use iwctl to connect via wifi

```bash
iwctl
station wlan0 connect <ESSID>
```

- set a root password
- scp the two files into installation root
- execute `arch.sh`
