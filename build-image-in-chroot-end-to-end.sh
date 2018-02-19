#!/bin/bash
set -x
set -e

BASEIMAGE_URL=https://rcn-ee.com/rootfs/2018-02-09/microsd/bone-ubuntu-16.04.3-console-armhf-2018-02-09-2gb.img.xz
TARGETIMAGE=kamikaze-rootfs.img

BASEIMAGE=`basename $BASEIMAGE_URL`

if [ ! -f $BASEIMAGE ]; then
    wget $BASEIMAGE_URL
fi

rm -f $TARGETIMAGE

xz -c -d $BASEIMAGE >> $TARGETIMAGE

truncate -s 4G $TARGETIMAGE
DEVICE=`losetup -P -f --show $TARGETIMAGE`

cat << EOF | fdisk ${DEVICE}
p
d
n
p
1
8192

p
w

EOF


e2fsck -f ${DEVICE}p1
resize2fs ${DEVICE}p1

mount ${DEVICE}p1 /mnt/root
mount -o bind /dev /mnt/root/dev
mount -o bind /sys /mnt/root/sys
mount -o bind /proc /mnt/root/proc

mkdir -p /mnt/root/run/resolvconf
cp /etc/resolv.conf /mnt/root/run/resolvconf/resolv.conf

# don't git clone here - if someone did a commit since this script started, Unexpected Things will happen
# instead, do a deep copy so the image has a git repo as well
mkdir -p /mnt/root/usr/src/Umikaze2

shopt -s dotglob # include hidden files/directories so we get .git
shopt -s extglob # allow excluding so we can hide the img files
cp -r `pwd`/!(*.img*) /mnt/root/usr/src/Umikaze2
shopt -u extglob
shopt -u dotglob

set +e # allow this to fail - we'll check the return code
chroot /mnt/root /bin/su -c "cd /usr/src/Umikaze2 && ./prep_ubuntu.sh && ./make-kamikaze-2.1.sh"

status=$?
set -e

umount /mnt/root/proc
umount /mnt/root/sys
umount /mnt/root/dev
umount /mnt/root

if [ $status -eq 0 ]; then
    echo "Looks like the image was prepared successfully - packing it up"
    ./generate-image-from-sd.sh $DEVICE
else
    echo "image generation seems to have failed - cleaning up"
fi

losetup -d $DEVICE
