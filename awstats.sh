#!/bin/sh
# Web page generator simple web server for wlan and 'wlanpoke' statistics
# Copyright (C) 2021 POMdev
# Derived from several web sources and wlanpoke,
#   see "https://stackoverflow.com/questions/16640054/minimal-web-server-using-netcat"
#
# This program is free software under GPL3 as stated in gpl3.txt, included.

Version="0.1.7 4/7/2021"

psEntry=`ps ax | grep "wlanpoke.sh -" | grep -v grep`
CmdLine=${psEntry##*/sh }
#/etc/wlanpoke/wlanpoke.sh -W slow -d /etc/log/
Options=${psEntry##*.sh }
#-W slow -d /etc/log/

#LOGDIR=`ps ax | grep "wlanpoke.sh -" | grep "\-d" | sed 's/.*-d \([^ ]*\).*/\1/g'`
#LOGDIR=`echo $Options | sed 's/.*-d \([^ ]*\).*/\1/g'`
# 0.1.7: | grep "\-d" restored, inadvertently deleted
LOGDIR=`echo $Options | grep "\-d" | sed 's/.*-d \([^ ]*\).*/\1/g'`
if [[ -z "$LOGDIR" ]] ; then
  LOGDIR="/var/log/"
fi


VersWLP="unknown $Options"
if [[ -r "Version" ]] ; then
  VersWLP=`cat "Version"`
fi



HOSTNAME=`cat "Hostname"`
if [[ -z "$HOSTNAME" ]] ; then
  HOSTNAME="WLAN"
fi


trq=`echo ${REQUEST##/}`        # get rid of root '/'
if [[ "$trq" == 'date' ]] ; then
  date
elif [[ -r "$trq" ]] ; then     # serve the file if it exists. To ... with the consequences!
  cat $trq
elif [[ "$trq" == 'RawFails' ]] ; then   # raw output for automated reports
  #echo $VersWLP "logs:" $LOGDIR
  echo $VersWLP
  echo `date -Iseconds` "(" `uptime` ")"
  cat ${LOGDIR}fping.txt
else
  echo -e "HTTP/1.1 200 OK\r"
  echo "Content-type: text/html"
  echo
  echo
  echo -e "<html><head><title>$HOSTNAME Statistics</title></head><body><h2>Wireless LAN Statistics</h2>\r\n"
  echo "<pre>"
  echo $VersWLP "logging to" $LOGDIR
  echo `date` "(" `uptime` ")"
  echo
  iwconfig eth1
  echo "</pre><h4>Ping: settings, events, and failed pings [0..n]; Step: full reset results, status; Gaps, Resets: # and recents</h4><pre>"
  cat ${LOGDIR}fping.txt
  echo "</pre><h4>recent AP scan results</h4><pre>"
  wpa_cli scan_results
  echo "</pre><h4>ar6002 chip statistics</h4><pre>"
  /lib/atheros/wmiconfig --getTargetStats
  echo "</pre><h4>important processes</h4><pre>"
  ps xf -o "pid,ppid,sess,pmem,vsz,size,rss,ni,pri,state,pcpu,start,time,args" | grep '[^]]$'       # 0.1.3 stat can show S<s which starts strikeout!!!
  echo -e "</pre>\r\n</body></html>"
fi
