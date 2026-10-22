curl := require('curl') ++ '-LJO --skip-existing'
gpg := require('gpg') ++ '--auto-key-retrieve --verify'
sha256sum := require('sha256sum') ++ '--ignore-missing -c'

url := 'https://mirrors.dotsrc.org/artix-linux/iso/'
iso := 'artix-base-dinit-20260813-x86_64'
sums := 'sha256sums'

[private]
@prepare-dir: && validate-dir
    echo ':: Downloading ISO image...'
    {{ curl }} {{ quote(url / sums) }}
    {{ curl }} {{ quote(url / iso + '.iso.sig') }}
    {{ curl }} {{ quote(url / iso + '.iso') }}

[private]
@validate-dir:
    echo ':: Validating ISO image...'
    {{ sha256sum }} {{ quote(sums) }}
    {{ gpg }} {{ quote(iso + '.iso.sig') }} {{ quote(iso + '.iso') }}

@prepare dir:
    cd {{ quote(dir) }} && {{ self }} prepare-dir

@partitioning device ram-size:
    cfdisk {{ quote(device) }}
    # Format ESP partition
    mkfs.vfat {{ quote(device + '1') }}
    # Format LUKS partition
    cryptsetup luksFormat --pbkdf=pbkdf2 {{ quote(device + '2') }}
    # Create LVM volume group
    vgcreate btw /dev/mapper/btw
    # Open LUKS partition
    cryptsetup open /dev/sdb2 vg-data
    # Create LVM volume group
    vgcreate vg-data /dev/mapper/vg-data
    # Create logical volumes
    lvcreate -L {{ quote(ram-size) }} -n swap vg-data
    lvcreate -l +100%FREE -n root vg-data
    # Format logical volumes
    mkswap /dev/vg-data/swap
    mkfs.btrfs /dev/vg-data/root
    # Mount logical volumes
    swapon /dev/vg-data/swap
    mount -o compress=zstd,noatime /dev/vg-data/root /mnt
    # Create btrfs subvolumes
    btrfs subvol create /mnt/@
    btrfs subvol create /mnt/@var
    btrfs subvol create /mnt/@home
    btrfs subvol create /mnt/@snapshots
    # Disable Copy on write (COW) for the @var subvolume
    chattr +C /mnt/@var
    # Unmount btrfs volume & mount the @ (root) subvolume
    umount /mnt
    mount -o compress=zstd,noatime,subvol=@ /dev/btw/root /mnt
    # Mount the ESP partition
    mkdir -p /mnt/boot/efi
    mount {{ quote(device + '1') }} /mnt/boot/efi
    # Mount the rest of the subvolumes
    mkdir -p /mnt/{var,home,.snapshots}
    mount -o compress=zstd,noatime,subvol=@home /dev/btw/root /mnt/home
    mount -o compress=zstd,noatime,subvol=@var /dev/btw/root /mnt/var
    mount -o compress=zstd,noatime,subvol=@snapshots /dev/btw/root /mnt/.snapshots
