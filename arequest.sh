#!/bin/sh
# Request parser for simple web server for wlan and 'wlanpoke' statistics
# Copyright (C) 2021 POMdev
# Derived from several web sources and wlanpoke, 
#   see "https://stackoverflow.com/questions/16640054/minimal-web-server-using-netcat"
#
# This program is free software under GPL3 as stated in gpl3.txt, included.

Version="0.1.1 3/16/2021"

#read stdin, launch script to extract then process request, and send it to a pipe, to be sent back to the browser.
export REQUEST=
while read -r line
do
  #line=$(echo "$line" | tr -d '\r\n')          # 0.1.1 do we really need this?
  # handle only simple GET requests, add code below for PUT processing.
  if echo "$line" | grep -qE '^GET /'           # if line starts with "GET /"
  then
    REQUEST=$(echo "$line" | cut -d ' ' -f2)    # extract the request
    # call a script here Note: REQUEST is exported, so the script can parse it (to answer 200/403/404 status code + content)
    ./awstats.sh > $WLPIPENAME                  # why wait?
  elif [ -z "$line" ]                           # empty line / end of request
  then
    #./awstats.sh > $WLPIPENAME
    echo "$REQUEST"                             # just to see how long it took for debugging
  fi
done

