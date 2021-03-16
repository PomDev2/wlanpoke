#!/bin/sh
# Web page generator simple web server for wlan and 'wlanpoke' statistics
# Copyright (C) 2021 POMdev
# Derived from several web sources and wlanpoke,
#   see "https://stackoverflow.com/questions/16640054/minimal-web-server-using-netcat"
#
# This program is free software under GPL3 as stated in gpl3.txt, included.

Version="0.1.1 3/16/2021"

echo -e "HTTP/1.1 200 OK\r"
echo "Content-type: text/html"
echo
echo
trq=`echo ${REQUEST##/}`        # get rid of root '/'
if [[ "$trq" == 'date' ]] ; then
  date
elif [[ -r "$trq" ]] ; then     # serve the file if it exists. To ... with the consequences!
  cat $trq
else
  echo -e "<html><head><title>WLAN Statistics</title></head><body><h2>Wireless LAN Statistics</h2>\r\n"
  echo "<pre>"
  uptime
  echo
  iwconfig eth1
  echo "</pre><h4>wlanpoke test settings (s,q,f) and failed pings [0..n] prior to recovery</h4><pre>"
  cat /var/log/fping.txt
  echo "</pre><h4>recent AP scan results</h4><pre>"
  wpa_cli scan_results
  echo "</pre><h4>ar6002 chip statistics</h4><pre>"
  /lib/atheros/wmiconfig --getTargetStats
  echo "</pre><h4>related processes</h4><pre>"
  ps a -F
  echo -e "</pre>\r\n</body></html>"
fi
