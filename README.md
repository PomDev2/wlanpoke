# wlanpoke
Mitigate Wireless Connectivity Loss in Squeezebox Radios

Version 0.7.0

Introduction

The wlanpoke software attempts to mitigate the "Wireless Connectivity Loss" issues suffered by the current version Squeezebox Baby radio software. The software periodically tests the wireless network, and if it fails for a while, restarts the wireless system without rebooting. The resulting network outage is under a minute, which may or may not interrupt music playback for a time or until resumed.

Connected ssh sessions frequently stay open during a restart.

The software sends failure incident report 'logs' to a computer running netcat (nc or ncat) as a server or a similar tcp logger. This computer should have enough disk space to accommodate log files. One or multiple servers on one or more machines can be used, and the software is configured to report to one of them.

Besides mitigating the wireless connectivity issue, the software instruments the radio's wireless behavior, and this data may be useful to developers troubleshooting the issues. However, you may not want that data collected and/or preserved. Fortunately, affirmative steps are required to setup and enable data logging. Also, the software has the option of disabling logging.

The software is implemented as the shell script "wlanpoke.sh." plus supporting files and documentation. There is also an optional script simple 'web server' to serve statistics to a web browser.

This software has been rushed together in response to an emergency of constantly failing radios. Versions have been keeping the author's 4 SB and 2 UE radios connected for 6 months as of this writing. Several users have downloaded previous versions, and they have reported that it has generally worked to keep their radios usable. This software is just a temporary partial mitigation of a serious reliability issue that has arisen during 2020. There are many un- or under-tested functions and features, multitudes of bugs, questionable methods, and coding ugliness. Please assist in pointing these out or fixing them.

We hope this software will become obsolete when the root causes of the unreliability have been fixed. In the mean time, your kind suggestions and improvements are appreciated. Please feel free to modify and adapt the scripts for your own purposes. And please feel free to join the effort to find real lasting solutions to this issue.

Please address your responses to the slimdevices forum.
