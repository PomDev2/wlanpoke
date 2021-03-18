#!/bin/sh
# Combine and upload wlanpoke logs to tftpd server
# Copyright (C) 2020, 2021 POMdev
#
# This program is free software under GPL3 as stated in gpl3.txt, included.
Version="0.1.0 3/18/2011"

FSERVER="192.168.0.4"
if [[ ! -z "$1" ]] ; then
  FSERVER=$1
fi
x="/var/log/wlanerr.log"
cat $x.3 $x.2 $x.1 $x.0 $x > t.log		# primitive: fails if all 5 logs do not exist.
FNAME=`cat /etc/wlanpoke/Version | cut -d" " -f 1`
if [[ -z "FNAME" ]] ; then
  FNAME=`hostname`
fi
FNAME=`echo $FNAME"_"``date -Is | sed "s/T/_/g;s/:/-/g;s/[+-]...0$//"`".log"
echo "Uploading $FNAME to $FSERVER"
tftp -p -l t.log -r $FNAME $FSERVER && echo Ok || echo Failed $?
rm t.log
