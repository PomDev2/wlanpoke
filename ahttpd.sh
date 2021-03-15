#!/bin/sh
# Simple web server for wlan and 'wlanpoke' statistics
# Copyright (C) 2021 POMdev
# Derived from several web sources and wlanpoke, 
#   see "https://stackoverflow.com/questions/16640054/minimal-web-server-using-netcat"
#
# This program is free software under GPL3 as stated in gpl3.txt, included.

Version="0.1.0 3/15/2021"

QUICKSVR="yes"          # set yes to enable periodic transmission of link statistics (0.5.0)
TCPPORT="8080"          # 1121 is default
APPDIR=$(dirname "$0")  # where the app files are located...

Help() {
    echo
    echo "Usage: $0 [options]"
    echo
    echo " -p * http server port (default $TCPPORT)"
    echo " -F   run slower 'full server' instead of default quick server (default NOT $QUICKSVR)"
    echo " -c   show copyright and license notice and exit"
    echo " -h   help and version ($Version)"
    echo
    echo "    * requires a reasonable value: no special chars, options are not validated."
    echo
    exit 0
}


CheckVal() {
    if [[ -z "$2" ]] ; then
      echo "$1" "requires a value"
      exit 1
    fi
}

while [ "$#" -ne 0 ]
do
case $1 in
        -p )    CheckVal $1 $2  ; shift ;   TCPPORT="$1"    ;;
        -F )    QUICKSVR="no"						;;
        -c )    cat "$APPDIR"/gpl3.txt  ;   exit 0  ;;
        -h )    Help            ;;
        * )     echo "Unsupported argument: '"$1"'" ;   exit 1
    esac
    shift
done

echo "$0 $Version"

# kill any previous instance (also kill any child processes)
PIDFILE="/var/run/ahttpd.pid"     # kill or be killed, Name hard coded.

KillApp () {
  if [ -r "PIDFILE" ] ;  then
    PID=`cat "$PIDFILE"`
    echo "Killing process $PID"     
    kill -TERM '-'$PID		# kill child processes, too
    kill -0 $PID >/dev/null 2>&1
    rm "$PIDFILE"
  fi
}
                                                      
# we are running now
KillApp                         # kill any app still running
killall nc						# stopgap: kill any rogue nc 'servers' (sorry wlanpoke if we stepped on you)
# we are the new app process
PID=$$                          # not $!
echo "$PID" > $PIDFILE

if [[ "$QUICKSVR" == "yes" ]] ; then
  while true; do ./awstats.sh | nc -lp $TCPPORT; done
else
  # potential 'full service' web server uses 3 scripts, 4 processes: this main controller, a request parser, and one (or more) content generators.
  export WLPIPENAME="wlpipe"
  rm -f $WLPIPENAME
  mkfifo $WLPIPENAME
  trap "rm -f out" EXIT
  while true
  do
    cat $WLPIPENAME | nc -lp $TCPPORT | ./arequest.sh
  done
fi
