#!/bin/bash
#Check if this is run with sudo, and exit otherwise
if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit
fi
dev=${1}
if [ ! -n "$dev" ] ; then
    echo "error"
    exit
fi
ls ${dev} > /dev/null 2>&1
if [ $? != "0" ]; then
    echo ls ${dev}: No such file or directory
    exit
fi

echo "Associating loopback device to image"
sudo losetup /dev/loop100 --partscan --show $dev

ls /dev/loop100p1  > /dev/null 2>&1
if [ $? != "0" ]; then
    echo ls /dev/loop100p1:  No such file or directory
    exit
fi
ls /dev/loop100p2 > /dev/null 2>&1
if [ $? != "0" ]; then
    echo ls /dev/loop100p2: No such file or directory
    exit
fi

echo "Mounting the original device"
mkdir original_rootfs
mkdir original_boot
sudo mount /dev/loop100p1 original_boot
sudo mount /dev/loop100p2 original_rootfs

start_sector=8192
mid_sector_left=532479
mid_sector_right=532480

total_MiB=$(df | grep /dev/loop100p2 | awk '{print $3}')
total_MiB=$(expr $total_MiB \/ 1024 \+ 300)
echo total_MiB is $total_MiB
total_sectors=$(expr $total_MiB \* 2048)
end_sector=$(expr $total_sectors \- 34)
echo "total_sectors=${total_sectors}, start_sector=${start_sector}, \
end_sector=${end_sector}"

echo Remove disk.img
rm disk.img

echo "Creating an empty image"
dd if=/dev/zero of=disk.img bs=1M count=$total_MiB

echo "Partitioning image"
sudo parted -s disk.img mklabel msdos
sudo parted -a none -s disk.img unit s mkpart  primary fat32 ${start_sector} ${mid_sector_left}
sudo parted -a none -s disk.img unit s mkpart  primary ext4 ${mid_sector_right} ${end_sector}

echo "Associating loopback device to image"
sudo losetup /dev/loop101 --partscan --show disk.img

echo "Adding label to partition"
sudo e2label /dev/loop101p1 boot
sudo e2label /dev/loop101p2 rootfs

echo "Change partition Type Id"
echo "
t
1
c
w
"| sudo fdisk /dev/loop101

echo "Formatting disk.img"
sudo mkfs.vfat -F 32 /dev/loop101p1
sudo mkfs.ext4 /dev/loop101p2

echo "Mounting new rootfs and boot"
mkdir boot
mkdir rootfs
sudo mount /dev/loop101p1 boot
sudo mount /dev/loop101p2 rootfs

echo "Sync Files"
rsync -avz original_rootfs/ rootfs
rsync -avz original_boot/ boot
old_uuid=$(sudo blkid /dev/loop100 | awk -F '"' '{print $2}')
new_uuid=$(sudo blkid /dev/loop101 | awk -F '"' '{print $2}')
echo "old uuid is $old_uuid, and new uuid is $new_uuid"

sudo sed -i -e "s/$old_uuid/$new_uuid/g" boot/cmdline.txt
sudo sed -i -e "s/$old_uuid/$new_uuid/g" rootfs/etc/fstab
cat boot/cmdline.txt
cat rootfs/etc/fstab 


echo "Umounting devices"
sleep 3
sudo umount original_rootfs
sudo umount original_boot
sudo losetup -d /dev/loop100
sudo umount rootfs
sudo umount boot
sudo losetup -d /dev/loop101
sudo rm original_rootfs -r
sudo rm original_boot -r

sudo fdisk -l disk.img
sudo parted -s disk.img p

echo "Compressing image"
gzip disk.img
