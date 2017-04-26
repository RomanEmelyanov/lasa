#!/bin/sh

FILENAME=$1
if [ ! -f "$FILENAME" ]; then
  echo "USAGE: $0 /path/to/asa.bin/image"
  exit 1;
fi
LASA="l$FILENAME"
ISOFILE=`echo $LASA | tr ".bin" ".iso"`
TMPDIR="tmp_$LASA"
ISODIR="iso_$LASA"
BEGIN=`binwalk -y='gzip' $FILENAME | grep rootfs | awk '{print $1;}'`
END=`binwalk --raw="\x0B\x01\x64\x00\x00" $FILENAME | grep 0 | tail -1 | awk '{print $1;}'`
SIZE=`expr $END - $BEGIN`
echo "Size of rootfs.img is $SIZE"
dd if=$FILENAME of=rootfs.img.gz skip=$BEGIN count=$SIZE bs=1 status=none
mkdir $TMPDIR
cd $TMPDIR
gunzip -c "../rootfs.img.gz" | cpio -i --no-absolute-filenames --make-directories

sed -i -e "s/\(VERBOSE=\).*/\1yes/" etc/init.d/rcS
sed -i -e "s/echo -n/echo/" etc/init.d/S10udev
sed -i -e "s#^fi\$#fi\necho '/bin/sh' >> /tmp/run_cmd#" asa/scripts/rcS
sed -i -e "/mount/d" asa/scripts/format_flash.sh
sed -i -e "s#mount=0#if [ ! -e /dev/hda1 ]; then /asa/scripts/format_flash.sh /dev/hda1 0 0 /dev/hda; fi\nmount=0#" asa/scripts/rcS.common

find . | cpio -o -H newc | gzip -9 > "../r00tfs.img.gz"
cd ..

cp $FILENAME $LASA

NEW_SIZE=$(stat -c%s "r00tfs.img.gz")
SIZE_DIFF=`expr $SIZE - $NEW_SIZE`
echo "Size of r00tfs.img is $NEW_SIZE"
dd if=/dev/zero bs=1 count=$SIZE_DIFF conv=notrunc,noerror status=none >> "r00tfs.img.gz"
dd if=r00tfs.img.gz of=$LASA seek=$BEGIN count=$SIZE bs=1 conv=notrunc,noerror status=none

mkdir $ISODIR
cd $ISODIR 
ISOLINUX_BIN=/usr/lib/syslinux/isolinux.bin
MKISOFS=`which mkisofs`
mkdir isolinux
cp $ISOLINUX_BIN isolinux/
cp ../r00tfs.img.gz initrd.gz
# v8 - 0x19000, v9 - 0x20800
KERNEL_OFFSET=133120
KERNEL_SIZE=`expr $BEGIN - $KERNEL_OFFSET`
dd skip=$KERNEL_OFFSET if="../$FILENAME" of="vmlinuz" bs=1 count=$KERNEL_SIZE

cat >isolinux/isolinux.cfg <<EEND
serial 0 
display boot.txt
prompt 1
default asa
label asa
  kernel /vmlinuz
  append initrd=/initrd.gz ide_generic.probe_mask=0x01 ide_core.chs=0.0:980,16,32 auto nousb console=ttyS0 bigphysarea=65536

EEND

cat >isolinux/boot.txt <<EOF
LASA for $FILENAME
To get console connect to serial port

EOF

$MKISOFS -o ../$ISOFILE -l \
	-b isolinux/isolinux.bin -c isolinux/boot.cat \
	-no-emul-boot -boot-load-size 4 -boot-info-table \
	./
cd ..
rm -rf r00tfs* rootfs* isolinux $TMPDIR $ISODIR

echo "Done!"
