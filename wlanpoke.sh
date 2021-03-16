#!/bin/sh
# Tests wireless connectivity and restarts the wlan if lost. Also, sends link quality statistics to optional tcp logger.
# Copyright (C) 2020 POMdev
#
# This program is free software under GPL3 as stated in gpl3.txt, included.

Version="0.7.1 3/16/2021"

LOGDIR="/var/log/"      # directory to store 'logs'
GWTXT="wgw.txt"         # where to write router's gateway ip or /dev/null
PINGLOG="wping.txt"     # store results of last good ping
STATLOG="stats.txt"     # save stats in circular buffer when ping fails (0.5.0)
FPINGLOG="fping.txt"    # store current results of failed pings, not a real log (0.7.0)

WSERVER="none"          # 'quick' launches simple server, 'slow' launches more capable server, or 'none' for no server. (0.7.0)
WSERVERPORT="8080"      # port for optional web server (0.7.0)

ERRLOG="wlanerr.log"    # store results of last good ping
LOGMAX='50'             # KB (x 1024) 1/4 of /var/log/messages.0, should be reasonable. Set to 0 to disable local log. (0.5.2)
LOGKEEP='3'             # highest rotated log number to keep. Set to 't' to trim instead of rotate log file
LOGDELIM="-"            # delimiter between incident records, appended by 'print' [("\n\n") and "--rec--" are too much] (0.5.0)
APPDIR=$(dirname "$0")  # where the app files are located...

PINGWAIT=1              # wait seconds for ping to succeed, otherwise a logged failure.
PINGSECS=2              # number of seconds to delay between ping tests. (0.7.0)
PINGRESET=6             # number of times for ping to fail before full reset. (0.7.0)
PINGQUICK=3             # number of times for ping to fail before quick reset. (0.7.0)

IFACE="eth1"            # the wlan is not wlan0 but rather eth1
GATEWAY="?"             # ip address of the router's gateway ip.
DTOK="?"                # last time ping was successful
DTNG=                   # first time ping failed. Initially empty.
DTQRST=                 # time this script started quickly resetting the wlan. Initially empty.
DTRST=                  # time this script started resetting the wlan. Initially empty.
DTEND=                  # when the reset was completed. Initially empty.
TSTSTATS="no"           # set yes to enable periodic transmission of link statistics (0.5.0)



# de-clutter logs: identify version using just the number with all 'dots' removed, e.g, '051'
VerSign=$(echo "$Version" | cut -d ' ' -f 1 | sed 's/\.//g')

# Horrible: get the ip of the slim server used at startup.
SERVER=`cat /etc/squeezeplay/userpath/settings/SlimDiscovery.lua | grep -o 'ip=\"[^\"]*' | cut -d "\"" -f 2`

# Log errors (after reconnection) to a simple tcp 'server' using nc. Note: Busybox 'nc' cannot send to syslog, which uses udp.
# you can have one server for all radios, or separate servers, one for each radio.
# Each separate server requires its own different port. One server for all radios uses just one port.
# For each server, launch 'nc' as a background process listening on one port and writing to a log file, e.g.,
#
#    nc -l -k -p 1121 >> t21a.log &
#
# where 't21a.log' is the log file name for the radio that will send to port 1121. Change this to suit. You may want to add a date stamp to the name.
# and '1121' above is the port number. Any unused port will do. Enter that port as the value to TCPPORT below:
TCPPORT="1121"          # 1121 is default

# The server ip address is by default the same ip as the slim server address, determined above.
TCPLOG=$SERVER
# To run the nc 'server' on another machine, uncomment the following line and enter the desired ip address.
#TCPLOG="192.168.0.2"   # hard coded ip address for nc 'server'
# to disable sending to a logging server, uncomment the following line:
#TCPLOG=                # do not send reports to a logger on a separate pc


# For 'friendlier' logs, use the Squeezeplay Radio name instead of the hostname, if possible.
HOSTNAME=`cat /etc/squeezeplay/userpath/settings/SlimDiscovery.lua | grep -o 'name=\"[^\"]*' | cut -d "\"" -f 2`
if [[ -z "$HOSTNAME" ]] ; then   # oops, that silly 'parser' above didn't work.
  HOSTNAME=`hostname`
fi

LOGLEVEL=3              # Numeric value, strings converted on assignment...
SLEEP=5                 # Initial delay seconds before running. The system should be good for this time.

# 0.7.0: decho - debug echo echos its arguments based up the first argument and the LOGLEVEL
decho () {
  if [[ -z "$1" ]]; then
    return
  elif [[ "$LOGLEVEL" -gt "$1" ]]; then
    shift
    echo "$*"   # one string separated by spaces IFS (spaces)
  fi
}
#decho 4 test 4
#decho 5 test 5
#decho 6 test 6

# Process the command line after setting the default values.
Help() {
    echo
    echo "Usage: $0 [options]"
    echo
    echo " -x   no tcp logging"
    echo " -t * tcp logging server ip address (default $SERVER)"
    echo " -p * tcp logging server port (default $TCPPORT)"
    echo " -d * directory to store small logs (default $LOGDIR)"
    echo " -b * rotated log numbers to keep (default $LOGKEEP, max=99, t=trim (slow))"
    echo " -s * max size (KB) before rotate or trim (default $LOGMAX, 0=disable, >1024=size in bytes)"     # 0.5.2 was -z
#    echo "      (rotated log files occupy ($LOGKEEP+2) x $LOGMAX storage)"
#    echo "      (trimmed log files delete the oldest entries keep the log size to the $LOGMAX)"
    echo " -r * log file record separator (default '$LOGDELIM', 0=none)"
    echo " -i * interface (default $IFACE)"
    echo " -H * hostname used by dhcpc and log messages (automatic default $HOSTNAME)"
    echo " -g * gateway (ping) destination ip address (automatic default) (future)"
    echo " -w * wait seconds for ping to succeed (default $PINGWAIT)"
    echo " -W * optional web server 'quick' for status or 'slow' for more, or 'none' (default '$WSERVER')"
    echo " -Wp * optional web server port (default $WSERVERPORT)"
    echo " -S * seconds to delay between ping tests (default $PINGSECS)"
    echo " -Q * number of pings to fail before quick reset (default $PINGQUICK, disable > $PINGRESET)"
    echo " -F * number of pings to fail before full reset (default $PINGRESET)"
    echo " -z * sleep seconds (default $SLEEP)"                                         # 0.5.2 was -s
    echo " -l * log level 0-8 (default $LOGLEVEL)"
    echo " -vt  enable verbose tcp logging of link quality statistics (default $TSTSTATS)"
    echo " -R   restart wireless network now and exit"
    echo " -k   kill (stop) any running $0 script and exit"
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

PIDFILE="/var/run/wlanpoke.pid"     # kill or be killed, Name hard coded.

KillApp () {
    if [ -r "$PIDFILE" ]
    then
      PID=`cat "$PIDFILE"`
      echo "Killing process $PID"
      #kill -TERM '-'$PID       # 0.7.0 kill child processes, too
      kill -TERM $PID        	# 0.7.1 busybox CANNOT kill child processes, too
      # Wait until app is dead
      kill -0 $PID >/dev/null 2>&1
    # while [ $? == 0 ]; do
    #     sleep 1
    #     kill -0 $PID >/dev/null 2>&1
    # done
      rm "$PIDFILE"
    fi
}

ResetQuick() {                          # 0.7.0
    DTQRST=`date -Iseconds`
    echo $DTQRST "Resetting wlan..."
    wpa_cli reassociate
    DTEND=`date -Iseconds`
    echo $DTEND "Waiting for successful ping..."
}

RestartNetwork() {
    DTRST=`date -Iseconds`
    echo $DTRST "Stopping and restarting wlan..."
    /etc/init.d/wlan stop && /etc/init.d/wlan start
    sleep 5       # was 10
    echo "Restarting dhcp"
    udhcpc -R -a -p/var/run/udhcpc.eth1.pid -b --syslog -ieth1 -H$HOSTNAME -s/etc/network/udhcpc_action
    DTEND=`date -Iseconds`
    echo $DTEND "Waiting for successful ping..."
}

# Override the defaults with the command line arguments, if any.
# no getopts in this ash
while [ "$#" -ne 0 ]
do
case $1 in
        -x )    TCPLOG=         ;;
        -t )    CheckVal $1 $2  ;   shift   ;   TCPLOG="$1"     ;;
        -p )    CheckVal $1 $2  ;   shift   ;   TCPPORT="$1"    ;;
        -d )    CheckVal $1 $2  ;   shift   ;   LOGDIR="$1"     ;;
        -s )    CheckVal $1 $2  ;   shift   ;   LOGMAX="$1"     ;;    # 0.5.2
        -b )    CheckVal $1 $2  ;   shift   ;   LOGKEEP="$1"    ;;    # 0.5.2
        -r )    CheckVal $1 $2  ;   shift   ;   LOGDELIM="$1"   ;;    # 0.5.2
        -i )    CheckVal $1 $2  ;   shift   ;   IFACE="$1"      ;;
        -H )    CheckVal $1 $2  ;   shift   ;   HOSTNAME="$1"   ;;
        -g )    CheckVal $1 $2  ;   shift   ;   GATEWAY="$1"    ;;
        -w )    CheckVal $1 $2  ;   shift   ;   PINGWAIT="$1"   ;;
        -W )    CheckVal $1 $2  ;   shift   ;   WSERVER="$1"    ;;    # 0.7.0    
        -Wp )   CheckVal $1 $2  ;   shift   ;   WSERVERPORT="$1" ;;   # 0.7.0    
        -S )    CheckVal $1 $2  ;   shift   ;   PINGSECS="$1"   ;;    # 0.7.0
        -Q )    CheckVal $1 $2  ;   shift   ;   PINGQUICK="$1"  ;;    # 0.7.0
        -F )    CheckVal $1 $2  ;   shift   ;   PINGRESET="$1"  ;;    # 0.7.0
        -z )    CheckVal $1 $2  ;   shift   ;   SLEEP="$1"      ;;    # 0.5.2 was -s
        -l )    CheckVal $1 $2  ;   shift   ;   LOGLEVEL="$1"   ;;    # converted to integer
        -vt )   TSTSTATS="yes"  ;;  # 0.5.0
        -R )    RestartNetwork  ;;
        -k )    KillApp                 ;   exit 0  ;;
        -c )    cat "$APPDIR"/gpl3.txt  ;   exit 0  ;;
        -h )    Help            ;;
        * )     echo "Unsupported argument: '"$1"'" ;   exit 1
    esac
    shift
done

# Prepend log directory to file names
GWTXT=${LOGDIR}$GWTXT
PINGLOG=${LOGDIR}$PINGLOG
FPINGLOG=${LOGDIR}$FPINGLOG     # store results of failed pings (0.7.0)FPINGLOG=${LOGDIR}$FPINGLOG      # store results of failed pings (0.7.0)
ERRLOG=${LOGDIR}$ERRLOG
STATLOG=${LOGDIR}$STATLOG
ERRLOGLAST=$ERRLOG".txt"        # 0.5.2: last error report, not a real log. Real log is created if tcp logger is disabled.

# entry in BYTES if over 1 MB. Sounds backwards, but make devastating errors more difficult.
if [[ "$LOGMAX" -le 1024 ]] ; then
  let "LOGMAX=$LOGMAX*1024"
fi
# Note: LOGKEEP == 0 means to use the cool but slow prune method.
if [[ "$LOGKEEP" -gt 99 ]] ; then
  LOGKEEP='99'
fi


# if [[ "$LOGLEVEL" -gt 2 ]] ; then
  # echo "wlanpoke" $Version
# fi
decho 2 "wlanpoke" $Version

if [[ "$LOGLEVEL" -gt 3 ]] ; then
  echo "Host name is" $HOSTNAME          # for debugging
  echo "Server is" $SERVER
  echo 'Logging' to: $GWTXT $PINGLOG $ERRLOG " and last report to " $ERRLOGLAST
  if [[ -n "$TCPLOG" ]] ; then
    echo "Sending to tcp logging server $TCPLOG port $TCPPORT"
  else
    echo "Not sending to tcp logging server"
  fi
  echo "Console loglevel is $LOGLEVEL"
  # Local log settings:
  if [[ "$LOGMAX" == "0" ]] ; then
    echo "Local log files disabled ($LOGMAX size)"
  else
    echo "Maximum local log size before rotation is $LOGMAX"
  fi
  if [[ ! "$LOGKEEP" == "p" ]] ; then
    echo "Keeping $LOGKEEP rotated log files"
  else
    echo "Trimming oldest log file entries to stay under $LOGMAX size"
  fi
  if [[ "$LOGDELIM" == "0" ]] ; then
    echo "No log file record separator ('LOGDELIM' disables)"
  else
    echo "Log file record separator is '$LOGDELIM'"
  fi

  echo "Waiting for $SLEEP seconds"
  echo "Running from $APPDIR"
fi

# Can we write to this directory? If not, stop
if echo > $GWTXT
then
  if [[ "$LOGLEVEL" -gt 3 ]] ; then
    echo "Ok writing $GWTXT"
  fi
else
  echo "Cannot write to $GWTXT"
  exit 2
fi

# we are running now
KillApp                         # kill any app still running
# we are the new app process
PID=$$                          # not $!
echo "$PID" > $PIDFILE

# if [[ "$LOGLEVEL" -gt 2 ]] ; then
  echo "Running as $PID"
# fi

# 0.7.1 had better change directory to the application folder to find those ./ files.
echo "$0  $APPDIR" `pwd`
cd "$APPDIR"
#pwd

# 0.7.0: launch optional server (e.g., for web) if requested. (hard coded)
if [[ "$WSERVER" == "quick" ]] ; then
  "$APPDIR/ahttpd.sh" -p $WSERVERPORT &
elif [[ "$WSERVER" == "slow" ]] ; then
  "$APPDIR/ahttpd.sh" -F -p $WSERVERPORT &
fi


IPADDR=$(wpa_cli status | grep ip_address | cut -d '=' -f2)
# radio's ip address
IPFIRST="0"                 # first byte to test for auto config link local ip address.
IPLAST=$IPADDR              # last byte for identification. Initially IPADDR for sign-on

# hello log on to the logging server
if [[ -n "$TCPLOG" ]] ; then
  echo `date -Iseconds` "$HOSTNAME.$IPLAST"_"$VerSign wlanpoke $PID at uptime:" `uptime` | nc -w 3 $TCPLOG $TCPPORT
fi

# -----------------------------
# Local LogFile stuff 0.5.2 new
# -----------------------------

# LogFile rotation -- a lot of code... 0.5.2 new

# what is the oldest log file now?
LOGOLD=0
LOGOLDNAME=""

# Log_findOldest find oldest log and optionally remove logs exceeding $LOGKEEP
Log_findOldest () {
  if [[ "$LOGKEEP" == "p" ]] ; then
    return 0
  fi
  LOGOLD=99
  while true; do
    LOGOLDNAME=`printf %s.%d $ERRLOG $LOGOLD`
    if [[ -f "$LOGOLDNAME" ]] ; then
      if [[ "$LOGOLD" -gt "$LOGKEEP" ]] ; then
        if [[ "$1" == "remove" ]] ; then
          echo "$LOGOLDNAME exceeds limit of $LOGKEEP, removing"
          rm "$LOGOLDNAME"
        else
          echo "$LOGOLDNAME exceeds limit of $LOGKEEP"
          break         # rotate starting at LOGKEEP or LOGOLD, whichever is lower.
        fi
      else
        break
      fi
    fi
    if [[ "$LOGOLD" -le 0 ]] ; then
      break
    fi
    let "LOGOLD=LOGOLD-1"
  done
}
# execute this now while we are waiting for the network to come up.
Log_findOldest remove

# Log_test1 creates test rotated log files 0..30 if they don't already exist.
# delete in next release.
Log_test1 () {
  LT=0
  Mx='30'
  while true; do
    LOGOLDNAME=`printf %s.%d $ERRLOG $LT`
    echo "$LOGOLDNAME"
    if [[ -f "$LOGOLDNAME" ]] ; then
      echo "$LOGOLDNAME exists"
    else
      echo "$LT" > $LOGOLDNAME
    fi
    let "LT=LT+1"
    if [[ "$LT" -gt "$Mx" ]] ; then
      break
    fi
  done
}
#Log_test1

# Log_rotate rotates logs if the $LOGKEEP is not '
Log_rotate () {
  if [[ "$LOGKEEP" == "p" ]] ; then
    return 0
  fi

  LRto=$LOGKEEP
  while true; do
    let "LRfr=LRto-1"
    frname=`printf %s.%d $ERRLOG $LRfr`
    toname=`printf %s.%d $ERRLOG $LRto`
    if [[ "$LRto" -le 0 ]] ; then
      frname=$ERRLOG
    fi
    if [[ "$LRto" -eq "$LOGKEEP" ]] ; then   # does this test really save time?
      if [[ -f "$toname" ]] ; then
        rm "$toname"
      fi
    fi
    if [[ -f "$frname" ]] ; then
      mv "$frname" "$toname"
    fi
    if [[ "$LRto" -le 0 ]] ; then
      break
    fi
    let "LRto=LRto-1"
  done
  touch $ERRLOG     # create new, empty error log
}
#Log_rotate

# LogFile_limit removes the first record from the $ERRLOG log file if it is larger than the $LOGMAX limit
# uses time consuming sed > tmp ; rm ERRLOG ; mv tmp ERRLOG ; sequence to prune records.
# if too slow, use 0, 1, 2, ... rotation, which is also slow if large numbers of backups are kept.
LogFile_limit () {
  if [[ -f "$ERRLOG" ]] ; then
    logsiz=`wc -c "$ERRLOG" | awk '{print $1}'`
    if [[ "$logsiz" -gt "$LOGMAX" ]] ; then
      if [[ "$LOGLEVEL" -gt 5 ]] ; then
        echo "$logsiz exceeds $LOGMAX..."
      fi
      if [[ "$LOGKEEP" == "p" ]] ; then
        # ok, slowly prune the log file. Each call deletes the one oldest entry. Call periodically.
        # delete from the first line to the record delimiter
        sed "1,/$LOGDELIM/d" "$ERRLOG" > "$ERRLOG"".tmp" ; rm "$ERRLOG" ; mv "$ERRLOG"".tmp" "$ERRLOG"   # ; wc "$ERRLOG" ; head "$ERRLOG"
      else
        Log_rotate
      fi
    fi
  fi
}

# LogFile_save Save a real log to ERRLOG 0.5.2 new. Optional first argument specifies what to save:
#  (nothing) save ERRLOGLAST, "RS" record separator, FileName that file if exists, otherwise all the arguments concatenated.
LogFile_save () {
  # Trim the log file, if it exists, to a specified size
  if [[ "$LOGMAX" -gt 0 ]] ; then
    LogFile_limit                               # rotate or prune oldest entry if too log file too large
    # append the current error report to the log file, but first, a delimiter, unless the log is new.
    # 0.6.2: moved below: always begin with record separator
    # if [[ ! -s "$ERRLOG" ]] ; then
    #   printf "%s\n" $LOGDELIM >> $ERRLOG
    # fi

    # append the current error report, or the argument if any
    if [[ -z "$1" ]] ; then
      cat "$ERRLOGLAST" >> $ERRLOG
    elif [[ "$1" == "RS" ]] ; then              # 0.6.2: begin with record separator (when requested)
      printf "%s\n" $LOGDELIM >> $ERRLOG        # printf supports additional "\n" in LOGDELIM if desired.
    elif [[ -f "$1" ]] ; then                   # pass any file name, and if it exists, cat it
      cat "$1" >> $ERRLOG
    else
      echo "$@" >> $ERRLOG
    fi
  fi
}

# say hello to the log
LogFile_save `date -Iseconds` "$HOSTNAME.$IPLAST"_"$VerSign wlanpoke $PID at uptime:" `uptime`

# -----------------------------------------
# Circular Buffer stuff for link statistics
# -----------------------------------------
# ash shell Circular Buffer without using arrays[]. no arrays in ash.?!?
# 0.5.1 use the eval function with safe parameters to implement a0..a# separate variables...
# CB_SIZE could be configured on the fly.

CB_SIZE=8       # could be an -option
CB_HEAD=0
CB_TAIL=0

# CB_put saves its arguments into the next ($HEAD) buffer position.
# To Do: Support quotes
CB_put () {
  # str=$@
  # echo $str
  eval "a$CB_HEAD='$@'"
  let "CB_HEAD=CB_HEAD+1"
  if [[ $CB_HEAD -ge $CB_SIZE ]] ; then
    CB_HEAD=0
  fi
}

# CB_getEntry returns the specified entry into global string $out
# returns the specified index number the entry does not exist
out=''
CB_getEntry () {
  local R=a$1
  eval out='$'$R
  # echo $1 $out
}

# CB_getAll copies the last $CB_SIZE into a single global string $outA
outA=''
nl=$'\n'        # magic 'string' type

CB_getAll () {
  outA=''
  CB_TAIL=$CB_HEAD
  while true; do
    CB_getEntry $CB_TAIL
    if [[ -z "$outA" ]] ; then
      outA=$out
    else
      outA=$outA"$nl"$out
    fi
    let "CB_TAIL=CB_TAIL+1"
    if [[ $CB_TAIL -ge $CB_SIZE ]] ; then
      CB_TAIL=0
    fi
    if [[ $CB_TAIL -eq $CB_HEAD ]] ; then
      break
    fi
  done
  #echo $outA
}

# Initialize before we go any further
# CB_init   # don't need init, CB_getEntry returns index or blank if a# is non-existant
# Avoid quotes !
CB_test () {
  CB_put Hello, world.
  CB_put Waste not, want not.
  CB_put A stitch in time saves nine.
  CB_put He who laughs last, laughs best.
  CB_put The early bird gets the worm.
  CB_put Good news, everyone!
  CB_put Do not cast your pearls before swine.
# CB_put "Ain't that a shame."  # fails  unterminated quoted string
# CB_put According to Cameron (2013), “We must spell wurds [sic] correctly.”    # ...
  CB_put Try a little tenderness.
  CB_put "The Moving Finger writes; and, having writ,
Moves on: nor all your Piety nor Wit
Shall lure it back to cancel half a Line,
Nor all your Tears wash out a Word of it."

  CB_getAll
  IFS='^J'
  echo $outA
  # don't dare fool with IFS
IFS='
'
  echo $outA
}


# GetStats SaveStats UploadStats interface to main loop
LASTSTAT=''

GetStats () {
  LASTSTAT=`date -Iseconds`":"`iwconfig eth1 | grep -E -i 'Rate|Quality|excessive'`
  # add additional stats here - ping time might be userful.
  LASTSTAT=$LASTSTAT" "`cat $PINGLOG | grep -i 'time' | cut -d ' ' -f7`

  # 0.5.2 esperimental: add lengthy 'wpa_cli scan_results' to see if the scanner is losing the AP.
  # results of PREVIOUS scan
  LASTSTAT=$LASTSTAT" "`wpa_cli scan_results | grep -v -e interface -e signal`

  # request a new scan -- if we dare -- don't want to disrupt the existing connection unnecessarily.
  # wpa_cli scan

  CB_put $LASTSTAT
  # for testing only to quickly create large log files
  # LogFile_save $LASTSTAT
}

SaveStats () {
  oldIFS=$IFS
  CB_getAll
  IFS='^J'
  echo `date -Iseconds` $HOSTNAME.$IPLAST"_"$VerSign "Link Statistics" > $STATLOG
  echo $outA >> $STATLOG
  IFS=$oldIFS

  LogFile_save "$STATLOG"       # save a real log file.
}

UploadStats () {
  if [[ -n "$TCPLOG" ]] ; then      # 0.6.4: NOT if [[ -n TCPLOG ]] ; then
    cat "$STATLOG" | nc -w 3 $TCPLOG $TCPPORT
  fi
}

# ------------------------------------------------
# end of circular Buffer stuff for link statistics
# ------------------------------------------------

# go well beyond the full reset limit.
PINGLIST=$PINGRESET
let "PINGLIST=PINGRESET+2"

FailedPings_clear () {
  local i=0
  while true; do
    local R=fp$i
    eval $R=0
    if [[ $i -gt $PINGLIST ]] ; then
      break
    fi
    let "i=i+1"     # get +1 as well.
  done
}
FailedPings_clear

outP=''
FailedPings_getAll () {
  outP=''
  local i=0
  while true; do
    local R=fp$i
    eval x='$'$R
    if [[ -z "$outP" ]] ; then
      outP=$x
    else
      outP=$outP" "$x
    fi
    if [[ $i -gt $PINGLIST ]] ; then
      break
    fi
    let "i=i+1"     # get +1 as well.
  done
}
#FailedPings_getAll ; echo $outP

# store current results of failed pings to $FPINGLOG not a real log (0.7.0)
FailedPings_save() {        
  FailedPings_getAll
  # report parameters
#  echo "Ping Secs=$PINGSECS, Quick=$PINGQUICK, Full=$PINGRESET" > $FPINGLOG
  # report failures
#  echo "FailedPings[$PINGLIST]: $outP" >> $FPINGLOG
#  echo "Ping Secs=$PINGSECS, Quick=$PINGQUICK, Full=$PINGRESET, FailedPings[$PINGLIST]: $outP" >> $FPINGLOG
  echo "Ping" "$PINGSECS""s$PINGQUICK""q$PINGRESET""f Fails[$PINGLIST]: $outP" > $FPINGLOG
}
FailedPings_save
decho 5 `cat $FPINGLOG`

FailedPings_inc () {
  local R=fp$1
  eval x='$'$R
  let "x=x+1"
  eval $R=$x
}
FailedPings_inc 1



# CB_getEntry returns the specified entry into global string $out
# returns the specified index number the entry does not exist
out=''
FailedPings_getEntry () {
  local R=a$1
  eval out='$'$R
  # echo $1 $out
}



sleep $SLEEP

# Initialize loop variables
i=0
n=0
wgwSz=0

while true; do
  # do this only every so often. And not if ping has failed.
  if [ $i -eq 0 ] && [ $n -eq 0 ]; then
    # don't get the gateway if there is no ip address line (but it may be 169.154.x.x ...)
    if wpa_cli status | grep ip_address | cut -d '=' -f2 > "$LOGDIR"ip.txt
    then
      IPADDR=`cat "$LOGDIR"ip.txt`
      IPFIRST=$(echo $IPADDR | cut -d '.' -f 1)     #
      IPLAST=$(echo $IPADDR | cut -d '.' -f 4)      # aid machine identification in logs in case of duplicate names.
      if [[ $IPFIRST == "169" ]] ; then
        GATEWAY=""                                  # inadequate configuration
      else
        GATEWAY=`netstat -r -n | grep ^0.0.0.0 | cut -f2 | awk '{print $2}'`
      fi
      echo $GATEWAY > $GWTXT
      if [[ "$LOGLEVEL" -gt 5 ]] ; then
        echo $IPADDR $IPFIRST $IPLAST
        echo gateway $GATEWAY
      fi
    else
      echo > $GWTXT
      decho 3 "No WfFi ip address..."
    fi
    wgwSz=`echo $GATEWAY | wc -c`
  fi

  # 1.1.1.1 or larger.
  if [[ $wgwSz -lt 6 ]] ; then
    decho 6 $wgwSz "too small"
  elif ping -c 1 -W $PINGWAIT $GATEWAY > $PINGLOG
  then
    # if [[ $n -gt 1 ]] ; then
      FailedPings_inc $n            # 0.7.0: save ping statistics. 1 has additional count after reset.
    # fi
    DTOK=`date -Iseconds`
    decho 5 $i $DTOK $GATEWAY " ping ok"
    n=0
    if [[ -n "$DTRST" || -n "$DTQRST" ]] ; then     # 0.7.0: either one will do to send the logs after a successful ping.
      # Append to the error log.
      # 0.6.2: save the log file with first the failure, then the recovery
      # Bug: this keeps adding to the ERRLOGLAST report until the nc send is successful.
      # 0.6.2: eliminate multiple entries into ERRLOGLAST if the nc connection goes down
      if [[ -n "$DTEND" ]] ; then
        FailedPings_save                                        # 0.7.0
        # 0.6.2: Save the log file with first the failure, then the recovery, not after stats have been saved.
        LOGRECVY=$ERRLOGLAST".2nd"
        # echo $DTOK $HOSTNAME.$IPLAST"_"$VerSign failed $DTNG quick $DTQRST reset $DTRST up $DTEND `iwconfig $IFACE` `cat $PINGLOG` > $LOGRECVY
        echo $DTOK $HOSTNAME.$IPLAST"_"$VerSign failed $DTNG quick $DTQRST reset $DTRST up $DTEND `iwconfig $IFACE` `cat $FPINGLOG` > $LOGRECVY
        # FailedPings_getAll ; echo $outP >> $LOGRECVY            # 0.7.0
        LogFile_save $LOGRECVY
        cat $LOGRECVY >> $ERRLOGLAST
        DTEND=
      fi

      if [[ -n "$TCPLOG" ]] ; then      # 0.6.4: NOT if [[ -n TCPLOG ]] ; then
        decho 3 "Sending wlanerr.log to $TCPLOG $TCPPORT"
        if cat "$ERRLOGLAST" | nc -w 3 $TCPLOG $TCPPORT
        then
          decho 3 "Send Successful"
          DTRST=
          DTQRST=       # 0.7.0
          #DTEND=
          UploadStats   # the large stats are uploaded after the disconnect and reset entries.
        else
          decho 3 "Send Failed"
        fi
      else              # 0.5.2: handle no TCPLOG case: stop logging to the error log!
        DTRST=
        DTQRST=         # 0.7.0
        #DTEND=
      fi

    fi
    # save the current successful ping statistics
    GetStats
    DTNG=
  else
    if [[ -z "$DTNG" ]] ; then
      DTNG=`date -Iseconds`
      # Start a new single incident log, don't want to fill up the flash.
      echo $DTNG $HOSTNAME.$IPLAST"_"$VerSign $GATEWAY " ping failed" `iwconfig $IFACE` > $ERRLOGLAST
      # 0.6.2: save the log file with first the failure, then the recovery
      LogFile_save "RS"                 # 0.6.2: begin each disconnect event record with a separator
      LogFile_save

      if [[ "$LOGLEVEL" -gt 3 ]] ; then
        cat $ERRLOGLAST
      fi
      # save the first unsuccessful ping statistics, and write the last statistics to a file for later upload or examination
      GetStats
      SaveStats
    fi
    let "n=n+1"
    if [[ $n -gt $PINGRESET ]] ; then       # 0.7.0: was 6 # 2x6=12 seconds was 2x10=20 seconds
      FailedPings_inc $n
      RestartNetwork
      sleep 1       # was 5
      n=1
    elif [[ $n -eq $PINGQUICK ]] ; then     # 0.7.0: new. > $PINGRESET disables ResetQuick   -ge makes a mess of the FailedPings log.
      FailedPings_inc $n
      ResetQuick
    fi
  fi

  let "i=i+1"                       # i=$((i+1))  # doesn't work? ((i=i+1))
  if [[ $i -gt 10 ]] ; then
    i=0
    # for testing (0.5.0)
    if [[ $TSTSTATS == "yes" ]] ; then
      SaveStats
      UploadStats
    fi

    FailedPings_save        		# 0.7.0 for http display
	decho 5 `cat $FPINGLOG`			# 0.7.1: only if high debug level
    # the trim or prune method may require repeated calls.
    if [[ "$LOGKEEP" == "p" ]] ; then
      LogFile_limit
    fi
  fi
  sleep $PINGSECS                   # 0.7.0: was 2
done

# end
