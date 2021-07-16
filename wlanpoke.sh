#!/bin/sh
# Tests wireless connectivity and restarts the wlan if lost. Also, sends link quality statistics to optional tcp logger.
# Copyright (C) 2020, 2021 POMdev
#
# This program is free software under GPL3 as stated in LICENSE.md, included.

Version="0.8.4.1 4/6/2021"

LOGDIR="/var/log/"      # directory to store 'logs'. Alternative for troubleshooting: '/etc/log' (create directory first)
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

PINGWAIT=1              # 0.8.1: deprecated. wait seconds for ping to succeed, otherwise a logged failure.
PINGSECS=2              # number of seconds to delay between ping tests. (0.7.0)
PINGRESET=6             # number of times for ping to fail before full reset after successful ping. (0.7.0)
PINGQUICK=-1            # number of times for ping to fail before quick reset. 0.8.1: was 7 0.7.6: was 3. Disable when not testing. (0.7.0)

#FRWaitSecsMin=12       # Calculated == PINGRESET * PINGSECS. minimum time to hold off after a full reset.   0.8.1.0: 6 trials x 2 secs/trial
FRWaitSecsMax=60        # maximum time to hold off another full reset after a previous unsuccessful one. 0.8.2.7e: was 120
                        # Currently, the step increments but never decrements. A lengthy network outage (router reboot) would increment the step to the max, which would then wait the maximum time before resetting the radio during a wireless outage.
FRWaitStepPct=40        # instead of fixed steps, calc array from % increase.
                        # NO: 0 == Fixed WaitStep Seconds: $FRWaitSecsMin,18,27,40,60,90,120 or calc
                        #     to include a fixed step initialization function, see below.

TimeFmt=":"             # timestamp format. ":" for HH:MM:SS, "-" for HH-MM-SS, otherwise specified 'date' format, e.g., "-Isec" (0.8.3.1)
GapsListMax=120         # Maximum size of the LIFO GapsList report. (0.8.3.5c)
ResetsListMax=120       # Maximum size of the LIFO ResetsList report. (0.8.4.1)

IFACE="eth1"            # the wlan is not wlan0 but rather eth1
GATEWAY="?"             # ip address of the router's gateway ip.
DTOK="?"                # last time ping was successful
DTNG=                   # first time ping failed. Initially empty.
DTQRST=                 # time this script started quickly resetting the wlan. Initially empty.
DTRST=                  # time this script started resetting the wlan. Initially empty.
DTEND=                  # when the reset was completed. Initially empty.
#TSTSTATS="no"          # 0.8.2.1: deprecated, removed: 'yes' enables periodic link statistics transmission (0.5.0)
_=0                     # dummy variable to receive unneeded shell math output from $(( )),
                        # quicker and easier than 'let', for reference (0.8.1.0)



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
#    echo " -w * wait seconds for ping to succeed (default $PINGWAIT)"      # 0.8.2.2: deprecated, removed
    echo " -W * optional web server 'quick' for status or 'slow' for more, or 'none' (default '$WSERVER')"
    echo " -Wp * optional web server port (default $WSERVERPORT)"
    echo " -S * seconds to delay between ping tests (default $PINGSECS)"
    echo " -Q * number of pings to fail before quick reset (default $PINGQUICK, enable < $PINGRESET, disable -1)"
    echo " -F * number of pings to fail before full reset (default $PINGRESET)"
    echo " -z * sleep seconds (default $SLEEP)"                                         # 0.5.2 was -s
    echo " -l * log level 0-8 (default $LOGLEVEL)"
#    echo " -vt  enable verbose tcp logging of link quality statistics (default $TSTSTATS)"     # 0.8.2.2: deprecated, removed
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

# 0.8.3.4: save options for logging
Options=$@
#echo Options: $Options

# -----------------------------------------
# Time Functions
# -----------------------------------------

# 0.8.3.1: return an easier to read timestamp in $(Time_S)
# 0.8.3.1: tricky: use conditional to devine Time_S function according to $TimeFmt.
# TimeFmt="-"
# TimeFmt=":"
# TimeFmt="-Isec"

if [[ "$TimeFmt" == ":" ]] ; then
 Time_S () { date +%F_%H:%M:%S ; }
elif [[ "$TimeFmt" == "-" ]] ; then
 Time_S () { date +%F_%H-%M-%S ; }
else
 Time_S () { date "$TimeFmt" ; }
fi
# echo $(Time_S)

# Return unix 'time' or seconds since 1/1/1970 in $(Time_U). Use to calculate real elapsed time... (0.8.3.1)
Time_U () {
 date +%s
}

# Save launch time. (0.8.3.5)
tuLaunch=$(Time_U)
tsLaunch=$(Time_S)

# returns number of seconds since argument, or since launch if argument is null or <= 0
Elapsed_get () {
  local now=$(Time_U)
  local start=$1
  if [[ -z "$Start" ]] || [[ $start -le 0 ]] ; then
    start=$tuLaunch
  fi
  echo $(( now - start ))
}
# Elapsed_get $(( $(Time_U) - 20 ))
# Elapsed_get 1000
# Elapsed_get -1
# Elapsed_get


# -----------------------------------------
# Kill Previous Instance
# -----------------------------------------

PIDFILE="/var/run/wlanpoke.pid"     # kill or be killed, Name hard coded.

KillApp () {
    if [ -r "$PIDFILE" ]
    then
      PID=`cat "$PIDFILE"`
      echo "Killing process $PID"
      #kill -TERM '-'$PID       # 0.7.0 kill child processes, too
      kill -TERM $PID           # 0.7.1 busybox CANNOT kill child processes, too
      # Wait until app is dead
      kill -0 $PID >/dev/null 2>&1
      rm "$PIDFILE"
    fi
}

# -----------------------------------------
# Reset and Quick Logging Functions
# -----------------------------------------

# 0.8.0.0: quick interface for time stamped and IDd logging and messages
ADTmsg=""                                       # global for other uses

Log_addDateTime () {
  #echo "Log_addDateTime"
  ADTmsg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign: $*")   # 0.8.3.1 $(Time_S) was `date -Iseconds`
  echo $ADTmsg
  echo $ADTmsg >> $ERRLOG                       # LogFile_save $ADTmsg
  #echo $msg | nc -w 3 $TCPLOG $TCPPORT         # might work by now.
}


# 0.8.0.0: no longer used. Rely on wpa_cli to signal this, or just wait for dhcpc to do it itself when it feels like it.
Dhcp_renew() {                          # 0.7.5.2: try to renew the lease ourselves as a last resort.
    # 0.7.4.2 get the dhcp client process ID to signal dhcp client to USR1=renew the lease and gateway
    local uPID="/var/run/udhcpc.""$IFACE"".pid"
    # -s USR1 signals the udhcpc to renew the lease.
    kill -s USR1 `cat "$uPID"`
}

# 0.8.3.0 when we full restart wpa_cli, don't count that as an external restart.
wpa_cli_PID=`pidof wpa_cli`             # ResetQuick needs this running, or it has to signal for dhcpc renew itself.


# 0.7.5.2: Various commands (below) were tried in ResetQuick(), but renewing the lease seems to be best.
# However, it is supposed to happen because wpa_cli initiates a wpa_action to do that.
# Doing that in ResetQuick trys ot renew the lease before the reassociation, which takes some time, and fails.
# Make sure wpa_cli is running instead.
    # 0.7.5.0: do it again just in case a new wpa_cli hasn't fully come on-line.
    # 0.7.5.1: unreliable. it executes before the wireless has reassociated. rely on wpa_cli -a to request renew lease.
    # Dhcp_renew                        # this happens before the reassociation.

ResetQuick() {                          # 0.7.4 new requirement: keep jive happy 0.7.0
    DTQRST=$(Time_S)                    # 0.8.3.1: was `date -Iseconds`
    Log_addDateTime "Resetting wlan... $IFACE"                  # 0.8.0.0 log this activity
    wpa_cli reassociate
    DTEND=$(Time_S)                     # 0.8.3.1: was `date -Iseconds`
    Log_addDateTime "Quick: waiting for successful ping..."      # 0.8.0.0 log this activity
}


# 0.8.0.0: script can hang two ways: constantly resetting the wlan before a dhcp response is achieved,
# and some problem in the network drivers that takes a long time between
#Mar 26 21:23:53 root: wlan: starting
#   and what's this delay?
#Mar 26 21:31:06 root: Starting wpa_supplicant

RestartNetwork() {
    DTRST=$(Time_S)                # 0.8.3.1: was `date -Iseconds`
    Log_addDateTime "Full: Stopping and restarting wlan..."         # 0.8.2.5 0.8.0.0 log this activity #echo $DTRST "Stopping and restarting wlan..."
    /etc/init.d/wlan stop && /etc/init.d/wlan start
    # kill any remaining udhcpc before sleeping. Above stop also takes time.
    killall udhcpc                                                  # 0.8.0.0 why is it taking so long to start udhcpc?
    Log_addDateTime "wlan restarted, sleeping."                     # 0.8.0.0 log this activity
    sleep 5
    wpa_cli_PID=`pidof wpa_cli`                                     # 0.8.3.0 don't count this as an external restart.
    Log_addDateTime "Restarting dhcp"                               # 0.8.0.0 log this activity #echo "Restarting dhcp"
    udhcpc -R -a -p/var/run/udhcpc.eth1.pid -b --syslog -ieth1 -H$HOSTNAME -s/etc/network/udhcpc_action
    DTEND=$(Time_S)                # 0.8.3.1: was `date -Iseconds`
    Log_addDateTime "Full: waiting for successful ping..."       # 0.8.0.0 log this activity
}

# -----------------------------------------
# Optional Command Line Parameters
# -----------------------------------------

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
#        -w )    CheckVal $1 $2  ;   shift   ;   PINGWAIT="$1"   ;;    # 0.8.2.1: deprecated, removed
        -W )    CheckVal $1 $2  ;   shift   ;   WSERVER="$1"    ;;    # 0.7.0
        -Wp )   CheckVal $1 $2  ;   shift   ;   WSERVERPORT="$1" ;;   # 0.7.0
        -S )    CheckVal $1 $2  ;   shift   ;   PINGSECS="$1"   ;;    # 0.7.0
        -Q )    CheckVal $1 $2  ;   shift   ;   PINGQUICK="$1"  ;;    # 0.7.0
        -F )    CheckVal $1 $2  ;   shift   ;   PINGRESET="$1"  ;;    # 0.7.0
        -z )    CheckVal $1 $2  ;   shift   ;   SLEEP="$1"      ;;    # 0.5.2 was -s
        -l )    CheckVal $1 $2  ;   shift   ;   LOGLEVEL="$1"   ;;    # converted to integer
#        -vt )   TSTSTATS="yes"  ;;  # 0.5.0                          # 0.8.2.2: deprecated, removed
        -R )    RestartNetwork  ;;
        -k )    KillApp                   ;   exit 0  ;;
        -c )    cat "$APPDIR"/LICENSE.md  ;   exit 0  ;;        # 0.7.3 was gpl3.txt
        -h )    Help            ;;
        * )     echo "Unsupported argument: '"$1"'" ;   exit 1
    esac
    shift
done

# -----------------------------------------
# Parameter Expansion and Adjustment
# -----------------------------------------

# Prepend log directory to file names
GWTXT=${LOGDIR}$GWTXT
PINGLOG=${LOGDIR}$PINGLOG
FPINGLOG=${LOGDIR}$FPINGLOG     # store results of failed pings (0.7.0)FPINGLOG=${LOGDIR}$FPINGLOG      # store results of failed pings (0.7.0)
ERRLOG=${LOGDIR}$ERRLOG
STATLOG=${LOGDIR}$STATLOG
ERRLOGLAST=$ERRLOG".txt"        # 0.5.2: last error report, not a real log. Real log is created if tcp logger is disabled.
LOGRECVY=$ERRLOGLAST".2nd"      # 0.7.2: moved to assign only once

# entry in BYTES if over 1 MB. Sounds backwards, but make devastating errors more difficult.
if [[ "$LOGMAX" -le 1024 ]] ; then
  LOGMAX=$(( LOGMAX * 1024 ))       # 0.8.2.0: was let "LOGMAX=$LOGMAX*1024"
fi

# Note: LOGKEEP == 0 means to use the cool but slow prune method.
if [[ "$LOGKEEP" -gt 99 ]] ; then
  LOGKEEP='99'
fi

# 0.8.1.0: Guarantee that PINGSECS >= 1
if [[ $PINGSECS -lt 1 ]] ; then
  PINGSECS=1
fi


# -----------------------------------------
# Parameter Debug Report
# -----------------------------------------

decho 2 "wlanpoke" $Version

if [[ "$LOGLEVEL" -gt 3 ]] ; then
  echo "Host name is" $HOSTNAME          # for debugging
  echo "Server is" $SERVER
  echo 'Logging' to: $GWTXT $PINGLOG $ERRLOG " and last report to " $ERRLOGLAST " and " $LOGRECVY
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

# -----------------------------------------
# Environment Validation
# -----------------------------------------

# 0.7.6: create the log directory, if it does not exist. # shorter: [[ ! -d "$LOGDIR" ]] && mkdir $LOGDIR
if [[ ! -d "$LOGDIR" ]] ; then mkdir $LOGDIR ; fi

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

# -----------------------------------------
# Initialization and Log In
# -----------------------------------------

# we are running now
KillApp                         # kill any app still running
# we are the new app process
PID=$$                          # not $!
echo "$PID" > $PIDFILE

echo "Running as $PID"


# 0.7.1 had better change directory to the application folder to find those ./ files.
#echo "$0  $APPDIR" `pwd`
cd "$APPDIR"
#pwd

# 0.7.0: launch optional server (e.g., for web) if requested. (hard coded)
if [[ "$WSERVER" == "quick" ]] ; then
  "$APPDIR/ahttpd.sh" -p $WSERVERPORT &
elif [[ "$WSERVER" == "slow" ]] ; then
  "$APPDIR/ahttpd.sh" -F -p $WSERVERPORT &
fi

# 0.7.2 create a version file for reading by the status web page
#echo "$HOSTNAME $0 $Version" "launched (""$WSERVER"") $(Time_S)" > "$APPDIR"/Version
# 0.8.3.4 remove path from script name. include Options
# 0.8.3.5: include unix time, $tsLaunch was $(Time_S)
#echo "$HOSTNAME ${0##*/} $Version" "launched (""$WSERVER"") $tsLaunch $tuLaunch" > "$APPDIR"/Version
ScriptName=$0   # 0.8.3.4: use saved ScriptName remove path added $Options
echo "$HOSTNAME ${ScriptName##*/} $Version" "launched $tsLaunch $tuLaunch Options: $Options" > "$APPDIR"/Version
echo "$HOSTNAME" > "$APPDIR"/Hostname

IPADDR=$(wpa_cli status | grep ip_address | cut -d '=' -f2)
# radio's ip address
IPFIRST="0"                 # first byte to test for auto config link local ip address.
IPLAST=$IPADDR              # last byte for identification. Initially IPADDR for sign-on

# hello log on to the logging server
if [[ -n "$TCPLOG" ]] ; then
  # 0.8.3.4: added $Options 0.8.3.1: $(Time_S) was `date -Iseconds`
  echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign wlanpoke $Options $PID at uptime:" `uptime` | nc -w 3 $TCPLOG $TCPPORT
fi

# 0.8.0.0 Test new function Log_addDateTime
Log_addDateTime "$PID at uptime:" `uptime`


# 0.8.0.0: Save any the previous fpings.txt to a 'log' file
#timestamp=`ls -ale $FPINGLOG | sed -e "s/ */ /g" | cut -d' ' -f8-11`       # too bad no stat, too difficult
if [[ -f "$FPINGLOG" ]] ; then
  local timestamp=`date -r $FPINGLOG +'%Y-%m-%d %H:%M:%S'`
  #echo `date -Iseconds` "wlanpoke $PID, previous $timestamp:" `cat $FPINGLOG` "appended to $FPINGLOG.log"
  echo `date -Iseconds` "wlanpoke $PID, previous $timestamp:" `cat $FPINGLOG` >> "$FPINGLOG.log"
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
    _=$(( LOGOLD-- ))       # 0.8.2.0: was let "LOGOLD=LOGOLD-1"
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
    _=$(( LT++ ))           # 0.8.2.0: was let "LT=LT+1"
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
    LRfr=$(( LRto - 1 ))            # 0.8.2.0: was let "LRfr=LRto-1"
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
    _=$(( LRto-- ))         # 0.8.2.0: was let "LRto=LRto-1"
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
  # Save a log file unless its maximum size is zero
  if [[ "$LOGMAX" -gt 0 ]] ; then
    # Trim the log file, if it exists, to a specified size
    LogFile_limit                               # rotate or prune oldest entry if too log file too large
    # append the current error report, or the argument if any
    # append the current error report to the log file, but first, a delimiter, unless the log is new.
    if [[ -z "$1" ]] ; then
      decho 5 "Saving $ERRLOGLAST to $ERRLOG"               # 0.7.2: debug this... cat $ERRLOGLAST
      cat "$ERRLOGLAST" >> $ERRLOG
    elif [[ "$1" == "RS" ]] ; then              # 0.6.2: begin with record separator (when requested)
      printf "%s\n" $LOGDELIM >> $ERRLOG        # printf supports additional "\n" in LOGDELIM if desired.
    elif [[ -r "$1" ]] ; then                   # 0.7.2: was -f pass any file name, and if it can be read, cat it
      decho 5 "Saving $1 to $ERRLOG"            # 0.7.2: debug this...  cat $1
      cat "$1" >> $ERRLOG
    else
      echo "$@" >> $ERRLOG
    fi
  fi
}

# say hello to the log
LogFile_save "RS"                               # 0.7.2: include a separator
# 0.8.3.4: added $Options
LogFile_save "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign wlanpoke $Options $PID at uptime:" `uptime`    # 0.8.3.1: $(Time_S) was `date -Iseconds`


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
  eval "a$CB_HEAD='$@'"
  _=$(( CB_HEAD++ ))            # 0.8.2.0: was let "CB_HEAD=CB_HEAD+1"
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
    _=$(( CB_TAIL++ ))          # 0.8.2.0: was let "CB_TAIL=CB_TAIL+1"
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
  CB_put No good deed goes unpunished.
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

# -----------------------------------------
# Link Status for the Circular Buffer
# -----------------------------------------

# GetStats SaveStats UploadStats interface to main loop
LASTSTAT=''
WpaST="none"                            # 0.8.2.0: wpa_cli status report has COMPLETED and ip or other...

# 0.8.2.0: added "status: $WpaST" add additional stats here - ping time might be userful.
GetStats () {
  # # echo GetStats
  LASTSTAT=$(Time_S)":"`iwconfig eth1 | grep -E -i 'Rate|Quality|excessive'` # 0.8.3.1: $(Time_S) was `date -Iseconds`
  LASTSTAT=$LASTSTAT" status $WpaST "`cat $PINGLOG | grep -i 'time' | cut -d ' ' -f7`

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
  # 0.8.3.1: $(Time_S) was `date -Iseconds`
  IFS='^J'
  echo $(Time_S) $HOSTNAME.$IPLAST"_"$VerSign "Link Statistics" > $STATLOG
  echo $outA >> $STATLOG
  IFS=$oldIFS

  LogFile_save $STATLOG             # 0.7.2: try removing quoites.. save a real log file.
}

UploadStats () {
  if [[ -n "$TCPLOG" ]] ; then      # 0.6.4: NOT if [[ -n TCPLOG ]] ; then
    cat "$STATLOG" | nc -w 3 $TCPLOG $TCPPORT
  fi
}

# ------------------------------------------------
# end of circular Buffer stuff for link statistics
# ------------------------------------------------

# ------------------------------------------------
# FailedPings (and other) statistics array
# ------------------------------------------------

#PINGLIST=$PINGRESET
# PINGRESET + 1 catches recovery just after full reset -- never..., well hardly ever...
PINGLIST=$(( PINGRESET + 1 ))           # 0.8.2.6: one zero above reset, the rest sparse until FailedPingsLimit

#   0.8.2.6: NO, separate variables: 0.7.2 move the counters to the end of the failed ping list.
#   PINGLQUIK=$(( PINGRESET + 2 ))      # 0.8.2.0: was let "PINGLQUIK=PINGLFULL-1" count of quick resets.
#   PINGLFULL=$(( PINGRESET + 3 ))      # count of full resets. $PINGLIST
#   #PINGLQUIK=$PINGLIST                # 0.7.2 next to last entry
#   #let "PINGLQUIK=PINGLFULL-1"        # count of quick resets.
#   #PING_WPA=PINGLFULL                 # 0.7.5.0: new index to keep track of times restarting wpa_cli
#   PING_WPA=$(( PINGRESET + 4 ))       # 0.8.2.0: was let "PING_WPA=PINGLFULL+1"
#   PING_WPA_PID==$(( PINGRESET + 5 ))  # 0.8.1.0: new slot.
#   # list one more zero...
#   PINGLIST=$(( PINGRESET + 6 ))       # 0.8.2.0: was let "PINGLIST=PINGRESET+3"  was 3, make space for PING_WPA_PID

# Above had to change now that nF keeps counting and not wrapping to 1. The array has to be available for all results, sparse as they may be.
nQuickReset=0
nFullReset=0
nWPARestart=0
nWPAChanged=0

FailedPings_clear () {
  local j=0
  while true; do
    local R=fp$j
    eval $R=0
    if [[ $j -ge $PINGLIST ]] ; then    # 0.8.2.1 0..12 not 13
      break
    fi
    _=$(( j++ ))                    # 0.8.2.0: was let j++ # 0.8.2.0: was let "j=j+1"     # get +1 as well.
  done
}
FailedPings_clear

FPout=''                        # 0.8.2.4: renamed, was outP

FailedPings_get () {            # 0.7.5.0: return the count for a single entry
  local R=fp$1
  eval FPout='$'$R
}

# 0.8.1.0: support sparse array > $PINGLIST

FailedPingsHigh=$PINGLIST       # 0.8.1.0: handle sparse array > $PINGLIST
FailedPingsLimit=99             # 0.8.1.0: but not > 99

FailedPings_getAll () {
  FPout=''
  local j=0
  while true; do
    local R=fp$j
    eval x='$'$R
    # handle sparse array -gt $PINGLIST which includes adding the index: to the display
    if [[ ! -z "$x" ]] && [[ $j -gt $PINGLIST ]] ; then
      x=$j":"$x
    fi
    # only if there is an entry
    if [[ ! -z "$x" ]] ; then
      if [[ -z "$FPout" ]] ; then
        FPout=$x
      else
        FPout=$FPout" "$x
      fi
    fi
    # nothing more to list?
    if [[ $j -gt $FailedPingsHigh ]] ; then
      break
    fi
    _=$(( j++ ))                # 0.8.2.0: was let j++ # 0.8.1.0: was let "j=j+1"     # get +1 as well.
  done
  # 0.8.2.6: concatenate fixed name counters. 0.8.3.1: add "   " was " - " to make Fr easier to find in a quick scan.
  FPout="Qr:$nQuickReset Fr:$nFullReset   Wr:$nWPARestart Wc:$nWPAChanged  [ $FPout ]"
}


# store current results of failed pings to $FPINGLOG not a real log (0.7.0)
FailedPings_save() {
  FailedPings_getAll
  # report parameters 0.8.2.7e: correct spelling
  # 0.8.3.5: add elapsed seconds.
  echo "Ping" "$PINGSECS""s$PINGQUICK""q$PINGRESET""f Events, Fails[0..$FailedPingsHigh] $(Elapsed_get)s :    $FPout" > $FPINGLOG
}

FailedPings_save
decho 5 `cat $FPINGLOG`

# 0.8.1.0: support sparse array > $PINGLIST
FailedPings_inc () {
  local index=$1
  # limit so listing doesn't take so long...
  if [[ $index -gt $FailedPingsLimit ]] ; then
    index=$FailedPingsLimit
  fi
  # capture the maximum so far to speed up listing.
  if [[ $FailedPingsHigh -lt $index ]] ; then
    FailedPingsHigh=$index
  fi
  local R=fp$index
  eval x='$'$R

  _=$(( x++ ))              # 0.8.2.0: was let x++
  eval $R=$x
}
# FailedPings_inc 1 ; FailedPings_inc 10 ; FailedPings_inc 11 ; FailedPings_inc 44 ; FailedPings_inc 99 ; FailedPings_inc 22312
# FailedPings_getAll ; echo $FailedPingsHigh ; echo $FPout


# ------------------------------
#  Gaps and Resets Statistics
# ------------------------------

tuGapStart=0           # unix time of last failed ping (0.8.3.5)
tuGapEnd=$tuLaunch     # unix time of recovery from last failed ping (0.8.3.5)
tuOutageLast=0         # last outage seconds (0.8.3.5)
tuWorkingLast=0        # last working period seconds (0.8.3.5)

# add LIFO record of last "-outage+working," times. Gaps_inc called upon recovery.
GapsList=""            # LIFO report of last outage times, trimmed to $GapsListMax  (0.8.3.5)
GapsNo=0               # number of outages

Gaps_inc () {
  if [[ ${#GapsList} -gt $GapsListMax ]] ; then
    GapsList=${GapsList%\-*}
  fi
  _z=$(( ++GapsNo ))
  GapsList="-$tuOutageLast+$tuWorkingLast,"$GapsList
}

# Add the current status to the GapList report to allow calculating the clock time of each outage (0.8.3.5c)
# To compute the elapsed seconds to an entry, add the absolute values of the numbers to that entry
GapsLast=""            # current outage, working  (0.8.3.5b)
tuGapsNow=0            # Add to end of record as report time stamp

GapsNow () {
  tuGapsNow=$(Time_U)
  # is the connection Ok?
  if [[ $tuGapStart -eq 0 ]] ; then
    GapsLast="+$(( tuGapsNow - tuGapEnd ))"
  else
    GapsLast="-$(( tuGapsNow - tuGapStart ))+$tuWorkingLast"
  fi
  #echo $GapsLast      # we want to return 2 global values, cannot do this by echo.
}

# -------- Resets ----------

# add LIFO record of last "-outage+working," for reset times. Resets_inc called upon recovery.
ResetsList=""           # LIFO report of last outage times, trimmed to $ResetsListMax  (0.8.4.1)
ResetsNo=0              # number of resets

tuResetStart=0          # unix time of last failed ping before reset (0.8.4.1)
tuResetEnd=$tuLaunch    # unix time of recovery from last failed ping (0.8.4.1)
tuResetWorkingLast=0    # last period between resets seconds (0.8.4.1)
tuResetOutageLast=0     # last reset outage seconds (0.8.4.1)

Resets_inc () {
  if [[ ${#ResetsList} -gt $ResetsListMax ]] ; then
    ResetsList=${ResetsList%\-*}
  fi
  _z=$(( ++ResetsNo ))
  ResetsList="-$tuResetOutageLast+$tuResetWorkingLast,"$ResetsList
}

# Add the current status to the ResetsList report to allow calculating the clock time of each outage (0.8.4.1)
# To compute the elapsed seconds to an entry, add the absolute values of the numbers to that entry
ResetsLast=""            # current outage, working  (0.8.4.1)
tuResetsNow=0            # Add to end of record as report time stamp

ResetsNow () {
  tuResetsNow=$(Time_U)
  # is the connection Ok?
  if [[ $tuResetStart -eq 0 ]] ; then
    ResetsLast="+$(( tuResetsNow - tuResetEnd ))"
  else      # not working # elif [[ $tuGapEnd -eq 0 ]] ;
    ResetsLast="-$(( tuResetsNow - tuResetStart ))+$tuResetWorkingLast"
  fi
}


# -----------------------------------------
#  Full Reset Holdoff Trial (Time) Control
# -----------------------------------------

# 0.8.1.0: save list of FullFails indexed by WaitStep. Shows how close the recovery was to the next full reset
# entries are prepended, so list shows last first. This facilitates getting a maximum of the last n events to reduce the holdoff.
# aFRs stores steps [0..$FRWaitStepLast]
# FRWaitSecsMin=12 ; FRWaitSecsMax=120 ; FRWaitStepPct=40
FRWaitSecsMin=$(( PINGRESET * PINGSECS ))   # 0.8.2.7: calculate any initial value above
FRWaitStepLast=0

FullFails=0            # number of failed pings after the last full reset. (0.8.1.0) # 0.8.3.5 FullFails was b4 loop, moved here for RawFails reports.

FRWaitSecs_init () {
  local w=$FRWaitSecsMin
  local pct=$(( FRWaitStepPct + 100 ))
  FRWaitStepLast=0
  echo -n "$FRWaitStepPct% steps <= $FRWaitSecsMax: "
  while true; do
    echo -n $w" "
    local R=aFRs$FRWaitStepLast
    eval $R=$w
    w=$(( (++w * pct)/100 ))
    if [[ $w -gt $FRWaitSecsMax ]] ; then
      break
    fi
    _z=$(( ++FRWaitStepLast ))
  done
  echo " Max Index $FRWaitStepLast"
}
FRWaitSecs_init

# Fixed table WaitStep Seconds: 12,18,27,40,60,90,120   = can . source (include) the following:
# Example for fixed WaitStep table inclusion:
# . FixedFRstWait.sh
# FRstWait_initFixed () {
  # aFRs0=$FRWaitSecsMin
  # aFRs1=18
  # aFRs2=27
  # aFRs3=40
  # aFRs4=60
  # aFRs5=90
  # aFRs6=120
  # FRWaitStepLast=6
# }
# FRstWait_initFixed


# given a sleep step (0..$FRWaitStepLast), returns the number of seconds to hold off the next reset.
FRWaitSecs=$FRWaitSecsMin

FRWaitSecs_get () {
  local j=$1
  if [[ $j -gt $FRWaitStepLast ]] ; then
    j=$FRWaitStepLast
  fi
  local R=aFRs$j
  eval FRWaitSecs='$'$R
  if [[ $FRWaitSecs -lt $FRWaitSecsMin ]] ; then
    FRWaitSecs=$FRWaitSecsMin
  fi
}
# echo $FRWaitSecs ;
# FRWaitSecs_get 0 ; echo $FRWaitSecs
# FRWaitSecs_get 1 ; echo $FRWaitSecs
# FRWaitSecs_get 7 ; echo $FRWaitSecs
# FRWaitSecs_get 12 ; echo $FRWaitSecs


# 0.8.1.0: generates a report of recovery times index by sleep times into global SSout
# e.g.,     12:16,10,12, 18:14,14,13, 27: 40: 60: 90: 120:
FRstWaitStats_getAll () {
  SSout=''
  local j=0
  while true; do
    local R=aRSt$j
    eval x='$'$R
    R=aFRs$j
    eval y='$'$R
    x=$y":"$x
    if [[ -z "$SSout" ]] ; then
      SSout=$x
    else
      SSout=$SSout" "$x
    fi

    _=$(( j++ ))
    if [[ $j -gt $FRWaitStepLast ]] ; then
      break
    fi
  done
}
#FRstWaitStats_getAll ; echo  $SSout
#    echo $j $R $y $x

# Calculate and possibly reduce FRstStep given FullFails, number of trials failed before success. (0.8.3.0)
# adjust 3 trials upwards
FRstStep=0          # 0.8.2.7: current step in hold off times.

FRstWait_calculate () {
  local last=$1
  last=$(( last + 3 ))
  local secs=$(( last * PINGSECS ))
  local j=0
  while true; do
    local R=aFRs$j
    eval x='$'$R
    #echo "$secs -le $x"
    if [[ $secs -le $x ]] ; then
      break
    fi
    _=$(( j++ ))
    if [[ $j -ge $FRWaitStepLast ]] ; then
      break
    fi
  done
  if [[ $FRstStep -ne $j ]]; then
    #echo "Hold-off step $j was $FRstStep"   # 0.8.3.4 fix message
    echo "Last result $1 changed: hold-off step $j was $FRstStep"   # 0.8.3.5 add last result (RawFails).
    FRstStep=$j
    return 0
  fi
  return 1
}
# FRWaitSecsMin=12 ; FRWaitSecsMax=120 ; FRWaitStepPct=40 ; FRWaitSecs_init
# PINGSECS=2 ; FRstStep=0 ; FRstWait_calculate 44 ; echo $FRstStep
# SSout="12: 16: 25: 32: 48:"

FRstWaitStats_save() {
  #FailedPings_getAll
  FRstWaitStats_getAll
  # report parameters
  #echo -n "Recovery or reset by hold off seconds: $SSout" >> $FPINGLOG
  # 0.8.3.1: include the signal level at that time
  # 0.8.3.4: improve report
  LASTSTAT=`iwconfig eth1 | grep -E -i 'Rate|Quality|excessive'`
  #echo "Recovery or reset by hold off seconds: [ $SSout ] $(echo $LASTSTAT | awk '{print $2,$8,$10,$17}')" >> $FPINGLOG
  # 0.8.3.5: add :$FullFails to evaluate FRstWait_calculate()
  echo "Step $FRstStep:$FullFails, limit:results: [ $SSout ]   Wlan: $(echo $LASTSTAT | awk '{print $2,$8,$10,$17}')" >> $FPINGLOG
  #echo "-Disconnected+Connected $GapsList" >> $FPINGLOG
  #echo "-Gap+OK $GapsNo: $GapsList" >> $FPINGLOG
  GapsNow   # update global $tuGapsNow. $(GapsNow) doesn't.
  echo "Gaps:$GapsNo @$tuGapsNow -Gap+OK secs: $GapsLast,$GapsList" >> $FPINGLOG
  ResetsNow
  echo "Resets:$ResetsNo @$tuResetsNow -Gap+OK secs: $ResetsLast,$ResetsList" >> $FPINGLOG          # (0.8.4.1)
}

FRstWaitStats_save

# 0.8.1.0: given a $1 WaitStep (0..$FRWaitStepLast) and a resulting $2 $FullFails, prepends a list of $FullFails indexed by WaitStep
  # trim $x if too large. replace deleted entries with m=# of entries deleted.
  # aRSt stores statistics (0.8.2.5)
FRstWaitStats_inc () {
  local idx=$1
  if [[ $idx -gt $FRWaitStepLast ]] ; then
    idx=$FRWaitStepLast
  fi
  local secs=$2
  _=$(( secs *= PINGSECS ))        # 0.8.2.7e: was *= 2
  local R=aRSt$idx
  eval x='$'$R
  if [[ ${#x} -gt 20 ]] ; then
    x=${x%,*}
  fi
  x="$secs,"$x
  eval $R=$x
}

# FRstWaitStats_inc 3 6
# FRstWaitStats_inc 3 5 ; FRstWaitStats_inc 3 8 ; FRstWaitStats_inc 4 12 ; FRstWaitStats_inc 4 14 ; FRstWaitStats_inc 4 14
# FRstWaitStats_getAll ; echo  $SSout


# ----------------------------------
#  wpa_client Monitoring
# ----------------------------------

# 0.7.5.0: the wpa_cli app was not running on several radios, causing no lease renewal after reassociation.
# There was no indication of the app quitting or crashing, or us or some other process killing it.
# document this strange behavior, and recover from the issue.
#wpa_cli_PID=`pidof wpa_cli`             # ResetQuick needs this running, or it has to signal for dhcpc renew itself.

wpa_cli_status () {
    WpaST=$(wpa_cli status | grep -e wpa_state -e ip_add | cut -d '=' -f2 | awk '{printf("%s ",$0);}')      # 0.8.2.0
    #echo $WpaST
}


wpa_cli_check () {
    local PID=`pidof wpa_cli`
    # # echo wpa_cli_check
    # there may be multiple instances running, and perhaps none in the -B -a mode, so this is not exact.
    if [[ -z "$PID" ]] ; then
        echo "wpa_cli $wpa_cli_PID not running, re-starting"
        LogFile_save "wpa_cli ($wpa_cli_PID) not running, re-starting"
        /usr/sbin/wpa_cli -B -a/etc/network/wpa_action
        echo "wpa_cli started ($?)"
        PID=`pidof wpa_cli`
        _z=$(( ++nWPARestart ))         # 0.8.2.6: was FailedPings_inc $PING_WPA ; FailedPings_get $PING_WPA
        local msg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign" "wpa_cli process $PID re-launched $nWPARestart") # 0.8.3.1: $(Time_S) was`date -Iseconds`
        echo $msg
        LogFile_save $msg
        echo $msg | nc -w 3 $TCPLOG $TCPPORT
    else
      if [[ "$wpa_cli_PID" != "$PID" ]] ; then
        _z=$(( ++nWPAChanged ))         # 0.8.2.6: FailedPings_inc $PING_WPA_PID ; FailedPings_get $PING_WPA_PID
        local msg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign" "wpa_cli process $PID changed $nWPAChanged was $wpa_cli_PID") # 0.8.3.1: $(Time_S)
        echo $msg
        LogFile_save $msg
        echo $msg | nc -w 3 $TCPLOG $TCPPORT
      fi
    fi
    wpa_cli_PID=$PID
    wpa_cli_status
}

# do it now at launch.
wpa_cli_check

# ----------------------------------------
#  Ethernet/Wireless Choice Detection
# ----------------------------------------

# 0.8.2.0: check for wireless (eth1) not ethernet (eth0) interface and we will wait until this is not true.
AutoIFace="unk"

AutoIFace_check () {
  AutoIFace=$(cat /etc/network/interfaces | grep "auto eth" | cut -f2)
}

AutoIFace_isWLAN () {
  case "$AutoIFace" in
   *eth1*)  return 0 ;; # no error, it IS wlan
  esac
  return 1              # confusing, isn't it?
}

AutoIFace_check ; if AutoIFace_isWLAN ; then echo -n wlan ; else echo -n Ethernet ; fi ; wpa_cli_status ; echo " ${AutoIFace##auto} $WpaST"


# ----------------------------------------
#  Script exit functions
# ----------------------------------------

# 0.8.0.0: do something if we are exiting (but no auto restart...)
Script_exit () {
  echo "wlanpoke exiting"               # 0.8.2.4: note start of exit function
  FailedPings_save
  FRstWaitStats_save
  local msg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign" "wlanpoke $PID exiting: $FPout")    # 0.8.3.1: $(Time_S) was `date -Iseconds`
  echo $msg
  LogFile_save $msg
  echo $msg | nc -w 3 $TCPLOG $TCPPORT
  # try to save the fpings.txt to a 'log' file
  echo $msg >> "$FPINGLOG.log"
  # save the last few kernel ring buffer entries.
  dmesg | tail -n 30                    # dump to the console
  dmesg | tail -n 30 >> $ERRLOG
  # finally, try to save the messages file... trouble ahead here...
  if [[ -f "/var/log/messages" ]] ; then
    # don't use yet more memoery
    #msg=`tail -n 30 "/var/log/messages"`
    #echo $msg
    #LogFile_save $msg
    tail -n 30 "/var/log/messages" >> $ERRLOG
    tail -n 30 "/var/log/messages"      # dump to the console
  fi
  echo "bye now"
}
# Note: kill -9 will not execute the EXIT trap before exiting.
trap Script_exit EXIT                   # 0.8.0.0: call Script_exit() if we are exiting for any reason.


# ----------------------------------------
#  Main Loop
# ----------------------------------------

sleep $SLEEP                            # allow the network to come up before complaining that it is not up.

# Initialize loop variables
iLoop=0
nF=0                                    # 0.8.1.0: Failed ping count "nF" was 'n', too confusing.
wgwSz=0
iGWFails=0                              # 0.8.0.0: count of invalid GATEWAY Failures
PingOk=0                                # 0.8.0.0: count of ok pings to hold off initial reset until a connection is established after launch.
FRstCount=0                             # 0.8.0.0: count of current full resets, reset when ping succeeds
NextFull=$PINGRESET                     # 0.8.1.0: NextFull=n+FRWaitSecs/PINGSECS
iPrevWlan=1

while true; do

  # 0.8.0.0: Do this every time if the gateway is no good, sepeciallf if ping has failed.
  # if [ $iLoop -eq 0 ] && [ $nF -eq 0 ]; then            # do this only every so often. And not if ping has failed.
  # 0.8.0.1: Hey! the size of 0.0.0.0 is 7, not 6! but add \n and wc returns 8
  if [[ $iLoop -eq 0 ]] || [[ $wgwSz -le 8 ]] ; then     # 0.8.2.7: add back $iLoop
    # don't get the gateway if there is no ip address line (but it may be 169.154.x.x ...)
    if wpa_cli status | grep ip_address | cut -d '=' -f2 > "$LOGDIR"ip.txt
    then
      local GWo=$GATEWAY                            # 0.8.2.6a report gateway only if changed.
      IPADDR=`cat "$LOGDIR"ip.txt`
      IPFIRST=$(echo $IPADDR | cut -d '.' -f 1)     #
      IPLAST=$(echo $IPADDR | cut -d '.' -f 4)      # aid machine identification in logs in case of duplicate names.
      if [[ "$IPFIRST" == "169" ]] ; then           # 0.7.4: eliminate "sh: 169: unknown operand" error.
        GATEWAY=""                                  # inadequate configuration
      else
        #GATEWAY=$(netstat -r -n | grep ^0.0.0.0 | cut -f2 | awk '{print $2}')  # 0.8.2.0: may be 2 gateways eth0 and eth1
        GATEWAY=$(netstat -r -n | grep ^0.0.0.0 | cut -f2)
        GATEWAY=$(echo $GATEWAY | awk '{print $2}' | cut -d ' ' -f1)
        #echo gateway $GATEWAY
      fi
      echo $GATEWAY > $GWTXT
      # if [[ "$LOGLEVEL" -gt 5 ]] ; then
        #echo 5 "$IPADDR $IPFIRST $IPLAST gateway $GATEWAY"   # 0.8.2.7: combine lines.
      # echo gateway $GATEWAY
      # fi
      # 0.8.2.6a report gateway only if changed.
      if [[ ! "$GWo" == "$GATEWAY" ]] ; then
        local msg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign" "$IPADDR $IPFIRST $IPLAST gateway $GATEWAY")  # 0.8.3.1: $(Time_S) was`date -Iseconds`
        echo $msg
        LogFile_save $msg
      fi
    else
      echo > $GWTXT
      # this will be logged the first time below.
      decho 3 "No WfFi ip address..."
    fi
    wgwSz=`echo $GATEWAY | wc -c`
  fi
  # # echo "wpa_cli_check"
  wpa_cli_check                                     # 0.7.5.1: check this to see when the wpa_cli quits (evidently not ping failure).
  AutoIFace_check                                   # 0.8.1.0: get setting of Wireless or Ethernet?

  # # echo "iNG=1"
  # 0.8.0: keep counting toward full reset if the gateway is bad or ping fails.
  local iNG=1
  if [[ $wgwSz -le 8 ]] ; then                      # 0.8.0.0: was -lt 6 # 0.8.0 larver than 1.1.1.1 was "or larger."
    # Invalid gateway address. Keep failed iNG, send a message if the first time.
    local msg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign" "invalid ip or gateway: $WpaST")   # 0.8.2.0: add WpaST w pls
    echo $msg
    if [[ $iGWFails -eq 0 ]] ; then                 # 0.8.0.0: just one entry.
      LogFile_save $msg
    fi
    _=$(( iGWFails++ ))                             # 0.8.2.0: was let "iGWFails=iGWFails+1" # count number of passes until success...
  else                                              # Gateway seems valid.
    if [[ $iGWFails -gt 0 ]] ; then                 # 0.8.0.0: just one entry for the first instance.
      local msg=$(echo "$(Time_S) $HOSTNAME.$IPLAST"_"$VerSign" "valid ip and gateway: $WpaST after" $iGWFails "attempts. IP:" $IPADDR "Gateway:" $GATEWAY )
      echo $msg
      LogFile_save $msg
      echo $msg | nc -w 3 $TCPLOG $TCPPORT          # might work by now.
      iGWFails=0                                    # 0.8.0.0: reset failure message flag
    fi
    # finally, see if we can ping the gateway. Note: ping 0.0.0.0 succeeds, hence -le 6 for invalid gateway!
    if ping -c 1 -W $PINGWAIT $GATEWAY > $PINGLOG 2>&1 ; then
      iNG=0
    fi
  fi

  #echo check ping results
  if [[ $iNG -eq 0 ]]
  then
    # # echo ping ok
    DTOK=$(Time_S)                                  # ping succeeded. # 0.8.3.1: $(Time_S) was`date -Iseconds`
    decho 5 $iLoop $DTOK $GATEWAY " ping ok $nF"
    FailedPings_inc $nF                             # 0.7.0: save ping statistics. 1 has additional count after reset.
    # Calculate last outage seconds (0.8.3.5)
    if [[ $tuGapStart -ne 0 ]] && [[ $tuGapEnd -eq 0 ]] ; then
      tuGapEnd=$(Time_U)
      tuOutageLast=$(( tuGapEnd - tuGapStart ))
      Gaps_inc                                      # record LIFO report of -recovery+working, reports (0.8.3.5)
      tuGapStart=0                                 # reset but keep tuGapEnd to time space between failures
    fi

      # save Reset stats on first failure. (0.8.4.1)
    if [[ $tuResetStart -ne 0 ]] && [[ $tuResetEnd -eq 0 ]] ; then
      tuResetEnd=$(Time_U)
      tuResetOutageLast=$(( tuResetEnd - tuResetStart ))
      Resets_inc
      tuResetStart=0
    fi

    # 0.8.1.0: save full reset recovery statistics
    SSout=""
    if [[ $FRstCount -gt 0 ]] ; then
      # decho 5 "Recovered: FRstWaitStats_inc $nFullReset $FRstCount $FRstStep, $FullFails"
      FRstWaitStats_inc $FRstStep $FullFails
      # decho 5 "FRstWaitStats_getAll"
      FRstWaitStats_getAll                          # populate SSout.
      decho 5 "Recovered: FRstWaitStats_inc $nFullReset $FRstCount $FRstStep, $FullFails: $SSout"  # 0.8.3.4 missing $
      FRstWait_calculate $FullFails                 # 0.8.3.0
    fi

    if [[ -n "$DTRST" || -n "$DTQRST" ]] ; then     # 0.7.0: either one will do to send the logs after a successful ping.
      # Append to the error log.
      # 0.6.2: save the log file with first the failure, then the recovery
      # 0.6.2: eliminate multiple entries into ERRLOGLAST if the nc connection goes down
      if [[ -n "$DTEND" ]] ; then
        # 0.6.2: Save the log file with first the failure, then the recovery, not after stats have been saved.
        SaveStats                                               # 0.7.2: save these statistics only if we did a reset, was below after first ping failure.
        # decho 5 "FailedPings_save"
        FailedPings_save                                        # 0.7.0
        # decho 5 "FRstWaitStats_save"
        FRstWaitStats_save                                      # 0.8.2.0
        # decho 5 "FRstWaitStats_save done"
        # 0.7.2: sdd 'fails' count 0.8.3.5: add outage $tuOutageLast
        echo $DTOK $HOSTNAME.$IPLAST"_"$VerSign failed $DTNG quick $DTQRST reset $DTRST up $DTEND outage $tuOutageLast"s" `iwconfig $IFACE` fails $nF `cat $FPINGLOG` > $LOGRECVY
        decho 5 $FPINGLOG "Recovery saved to " $LOGRECVY        # cat $FPINGLOG ; cat $LOGRECVY
        LogFile_save $LOGRECVY                                  # 0.7.2 undo: try quotes : FAILS after a few times, don't know why: append $LOGRECVY to the $ERRLOG log file
        cat $LOGRECVY >> $ERRLOGLAST
        DTEND=
      fi

      if [[ -n "$TCPLOG" ]] ; then                  # 0.6.4: NOT if [[ -n TCPLOG ]] ; then
        decho 3 "Sending wlanerr.log to $TCPLOG $TCPPORT"
        if cat "$ERRLOGLAST" | nc -w 3 $TCPLOG $TCPPORT
        then
          decho 3 "Send Successful"
          DTRST=
          DTQRST=       # 0.7.0
          UploadStats   # the large stats are uploaded after the disconnect and reset entries.
        else
          decho 3 "Send Failed"
        fi
      else              # 0.5.2: handle no TCPLOG case: stop logging to the error log!
        DTRST=
        DTQRST=         # 0.7.0
      fi

    fi

    _=$(( PingOk++ ))               # 0.8.2.0: was let PingOk++
    # save the current successful ping statistics
    nF=0                            # 0.7.2 moved here so that the value can be used in reports above
    #FullFails=0                    # 0.8.2.5: nope: 0.8.2.4 don't keep this going...
    FRstCount=0                     # 0.8.0.0 count of current full resets, reset when ping succeeds (0.8.0.0)

    # 0.8.1.0: keep it where it is for now, can reduce based on statistics in later version.
    #NextFull=$PINGRESET            # 0.8.1.0: NextFull=n+FRWaitSecs/PINGSECS
    # 0.8.2.7: get the sleep limit, potentially from a custom array that overrides $PINGRESET, no need to add it to nF == 0
    FRWaitSecs_get $FRstStep
    NextFull=$(( FRWaitSecs / PINGSECS ))

    GetStats
    DTNG=
  elif [[ $PingOk -eq 0 ]] ; then
    echo "waiting for successful first ping"

  # 0.8.1.0: only if the wireless is in use.
  elif AutoIFace_isWLAN ; then
    # echo Failed $nF and AutoIFace_isWLAN
    # 0.8.1.0: limit Wireless/Ethernet messages to transitions.
    if [[ $iPrevWlan -eq 0 ]] ; then
      # 0.8.2.7: reset the limits and counters here.
      FRWaitSecs_get $FRstStep                   # 0.8.2.7: was $FRstCount
      # this may be too short for a first first time...
      local nSeconds=$(( FRWaitSecs + SLEEP ))
      local nNF=$(( nSeconds / PINGSECS ))       # was FRWaitSecs, but longer, please, this first time
      # 0.8.2.7: Preserve FullFails as the number of failed pings following the last reset.
      #msg="${AutoIFace##auto} $WpaST resuming operation step $FRstStep, resetting failed pings $nF and $FullFails to 0, $NextFull to $nNF, $nSeconds seconds."
      #FullFails=0
      msg="${AutoIFace##auto} $WpaST resuming operation step $FRstStep after $FullFails fails, resetting failed pings $nF to 0, $NextFull to $nNF, $nSeconds seconds."
      Log_addDateTime "$msg"
      nF=0
      NextFull=$nNF
      iPrevWlan=1
    fi

    # Calculate last working seconds (0.8.3.5)
    if [[ $tuGapStart -eq 0 ]] ; then
      tuGapStart=$(Time_U)
      tuWorkingLast=$(( tuGapStart - tuGapEnd ))
      tuGapEnd=0
    fi

    if [[ -z "$DTNG" ]] ; then
      DTNG=$(Time_S)                    # 0.8.3.1: $(Time_S) was`date -Iseconds`
      # Start a new single incident log, don't want to fill up the flash. 0.8.3.5: add working seconds
      echo $DTNG $HOSTNAME.$IPLAST"_"$VerSign $GATEWAY " ping failed after $tuWorkingLast""s" `iwconfig $IFACE` > $ERRLOGLAST
      # 0.6.2: save the log file with first the failure, then the recovery
      # However, there may not be a logged recovery, since the radio will not log a recovery unless it has done something to recover from.
      LogFile_save "RS"                 # 0.6.2: begin each disconnect event record with a separator
      LogFile_save                      # empty argument saves $ERRLOGLAST ...

      if [[ "$LOGLEVEL" -gt 3 ]] ; then
        cat $ERRLOGLAST
      fi
      # save the first unsuccessful ping statistics, and write the last statistics to a file for later upload or examination
      GetStats
      #SaveStats                            # 0.7.2: save these statistics only if we did a reset.
    fi
    _=$(( nF++ ))                           # 0.8.2.0: was let nF++  # 0.8.1: was let "nF=nF+1"

    if [[ $FRstCount -gt 0 ]] ; then        # 0.8.2.7d: was -ge # 0.8.2.5: only if we are in a failure
      _=$(( FullFails++ ))                  # 0.8.2.0: was let FullFails++ # number of times ping failed after full reset.
    fi

    decho 5 "Failed: $FullFails, $nF -eq $NextFull"
    if [[ $nF -eq $NextFull ]] ; then           # 0.8.1: was 6 # 2x6=12 seconds was 2x10=20 seconds was #if [[ $nF -gt $PINGRESET ]] ; then
      _z=$(( nFullReset++ ))                    # 0.8.2.6: was FailedPings_inc $PINGLFULL      # 0.7.2: don't interfere with the failed ping count.

      # save Reset stats on first failure. (0.8.4.1)
      if [[ $tuResetStart -eq 0 ]] ; then
        tuResetStart=$tuGapStart               # that happened a while ago at the first ping fail(ure)
        tuResetWorkingLast=$(( tuResetStart - tuResetEnd ))
        tuResetEnd=0
      fi

      # The previous reset failed, save that event. FullFails will be the max, meaning that the reset failed.
      if [[ $FRstCount -gt 0 ]] ; then          # 0.8.2.7d: was -ge
        decho 5 "Failed: FRstWaitStats_inc $nFullReset $FRstCount $FRstStep, $FullFails"
        FRstWaitStats_inc $FRstStep $FullFails  # 0.8.2.7 was $FRstCount
        _=$(( FRstStep++ ))                     # never goes down, for now
      fi
      RestartNetwork

      # 0.8.1.0: calculate NextFull failed ping trial count from seconds.
      FRWaitSecs_get $FRstStep              # 0.8.2.7: ws $FRstCount
      # decho 5 "FRWaitSecs_get $FRstStep = $FRWaitSecs"
      local incr
      incr=$(( FRWaitSecs / PINGSECS ))     # 0.8.2.0: was let incr=FRWaitSecs/PINGSECS   # guaranteed: PINGSECS >= 1
      _=$(( NextFull += incr ))             # 0.8.2.0: was let NextFull+=incr

      FRstWaitStats_getAll                  # 0.8.2.5L debugging
      Log_addDateTime "Full Reset # $FRstCount, step $FRstStep. Last recovery was $FullFails, next reset in $nF + $incr trials = $NextFull. + $FRWaitSecs seconds. $FRWaitSecsMin - $FRWaitSecsMax. History: $SSout"
      #nF=1                                 # 0.8.1.0: keep nF counting. No longer: start the counter over
      FullFails=0                           # 0.8.1: zero number of failed pings after the last full reset.
      _=$(( FRstCount++ ))                  # 0.8.2.0: was let FRstCount++  # count of current full resets, reset when ping succeeds
      # decho 5 "FRstCount = $FRstCount, FullFails = $FullFails"
    elif [[ $nF -eq $PINGQUICK ]] ; then    # 0.7.0: new. > $PINGRESET disables ResetQuick   -ge makes a mess of the FailedPings log.
      _z=$(( nQuickReset++ ))               # 0.8.2.6: was FailedPings_inc $PINGLQUIK     # 0.7.2: don't interfere with the failed ping count.
      ResetQuick
    fi
  else                                      # we are on the Ethernet.
    # echo Failed and NOT AutoIFace_isWLAN
    if [[ $iPrevWlan -eq 1 ]] ; then        # 0.8.1.0: limit Wireless/Ethernet messages to transitions.
      msg="${AutoIFace##auto} $WpaST suspending operation, resetting failed pings $nF to 0"
      Log_addDateTime "$msg"
      nF=0
      iPrevWlan=0
    fi
  fi

  _=$(( iLoop++ ))                      # 0.8.2.0: was let iLoop++ # 0.8.1.0: was let "i=i+1" # i=$((i+1)) doesn't work?
  if [[ $iLoop -gt 10 ]] ; then
    iLoop=0
    # # for testing (0.5.0)
    # if [[ $TSTSTATS == "yes" ]] ; then
      # SaveStats
      # UploadStats
    # fi

    FailedPings_save                # 0.7.0 for http display
    FRstWaitStats_save              # 0.8.2.0
    decho 5 `cat $FPINGLOG`         # 0.7.1: only if high debug level
    # the trim or prune method may require repeated calls.
    if [[ "$LOGKEEP" == "p" ]] ; then
      LogFile_limit
    fi
  fi
  sleep $PINGSECS                   # 0.7.0: was 2
done

# end
