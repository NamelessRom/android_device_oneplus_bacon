#!/sbin/sh

block=/dev/block/platform/msm_sdcc.1/by-name/boot;
ramdisk=/tmp/anykernel/ramdisk;
bin=/tmp/anykernel/tools;
split_img=/tmp/anykernel/split_img;

mkdir -p $ramdisk;
cd $ramdisk;
chmod -R 755 $bin;
mkdir -p $split_img;

# dump boot and extract ramdisk
dump_boot() {
  dd if=$block of=/tmp/anykernel/boot.img;
  $bin/unpackbootimg -i /tmp/anykernel/boot.img -o $split_img;
  gunzip -c $split_img/boot.img-ramdisk.gz | cpio -i;
}

# repack ramdisk then build and write image
write_boot() {
  cd $split_img;
  cmdline=`cat *-cmdline`;
  board=`cat *-board`;
  base=`cat *-base`;
  pagesize=`cat *-pagesize`;
  kerneloff=`cat *-kerneloff`;
  ramdiskoff=`cat *-ramdiskoff`;
  tagsoff=`cat *-tagsoff`;
  if [ -f *-second ]; then
    second=`ls *-second`;
    second="--second $split_img/$second";
    secondoff=`cat *-secondoff`;
    secondoff="--second_offset $secondoff";
  fi;
  if [ -f *-dtb ]; then
    dtb=`ls *-dtb`;
    dtb="--dt $split_img/$dtb";
  fi;
  cd $ramdisk;
  find . | cpio -o -H newc | gzip > /tmp/anykernel/ramdisk-new.cpio.gz;
  $bin/mkbootimg --kernel $split_img/boot.img-zImage --ramdisk /tmp/anykernel/ramdisk-new.cpio.gz $second --cmdline "$cmdline" --board "$board" --base $base --pagesize $pagesize --kernel_offset $kerneloff --ramdisk_offset $ramdiskoff $secondoff --tags_offset $tagsoff $dtb --output /tmp/anykernel/boot-new.img;
  dd if=/tmp/anykernel/boot-new.img of=$block;
}

replace_line() {
  if [ ! -z "$(grep "$2" $1)" ]; then
    line=`grep -n "$2" $1 | cut -d: -f1`;
    sed -i $line"s;.*;${3};" $1;
  fi;
}

# backup_file <file>
backup_file() { cp $1 $1~; }

########################################################

dump_boot;

backup_file fstab.bacon

# check if system is f2fs formatted
mount | grep -q '/system type f2fs'
F2FS=$?
if [ $F2FS -eq 0 ]; then
    replace_line fstab.bacon "/dev/block/platform/msm_sdcc.1/by-name/system       /system         ext4    ro,barrier=1                                                    wait" "/dev/block/platform/msm_sdcc.1/by-name/system       /system         f2fs    ro,noatime,nosuid,nodev,discard,nodiratime,inline_xattr,errors=recover wait";
fi

# check if data is f2fs formatted
mount | grep -q '/data type f2fs'
F2FS=$?
if [ $F2FS -eq 0 ]; then
    replace_line fstab.bacon "/dev/block/platform/msm_sdcc.1/by-name/userdata     /data           ext4    noatime,nosuid,nodev,barrier=1,data=ordered,noauto_da_alloc,errors=panic wait,check,encryptable=/dev/block/platform/msm_sdcc.1/by-name/reserve4" "/dev/block/platform/msm_sdcc.1/by-name/userdata     /data           f2fs    noatime,nosuid,nodev,discard,nodiratime,inline_xattr,errors=recover wait,nonremovable,encryptable=/dev/block/platform/msm_sdcc.1/by-name/reserve4";
fi

# check if cache is f2fs formatted
mount | grep -q '/cache type f2fs'
F2FS=$?
if [ $F2FS -eq 0 ]; then
    replace_line fstab.bacon "/dev/block/platform/msm_sdcc.1/by-name/cache        /cache          ext4    noatime,nosuid,nodev,barrier=1,data=ordered,noauto_da_alloc,errors=panic wait,check" "/dev/block/platform/msm_sdcc.1/by-name/cache        /cache          f2fs    noatime,nosuid,nodev,discard,nodiratime,inline_xattr,errors=recover wait";
fi

write_boot;
