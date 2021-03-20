# wlanpoke
Mitigate Wireless Connectivity Loss in Squeezebox Radios

Version 0.7.3

Introduction

The wlanpoke software attempts to mitigate the "Wireless Connectivity Loss" issues suffered by the current version Squeezebox Baby radio software. The software periodically tests the wireless network, and if it fails for a while, restarts the wireless system without rebooting. The resulting network outage is under a minute, which may or may not interrupt music playback for a time or until resumed.

Connected ssh sessions frequently stay open during a restart.

The software sends failure incident report 'logs' to a computer running netcat (nc or ncat) as a server or a similar tcp logger. This computer should have enough disk space to accommodate log files. One or multiple servers on one or more machines can be used, and the software is configured to report to one of them.

Besides mitigating the wireless connectivity issue, the software instruments the radio's wireless behavior, and this data may be useful to developers troubleshooting the issues. However, you may not want that data collected and/or preserved. Fortunately, affirmative steps are required to setup and enable data logging. Also, the software has the option of disabling logging.

The software is implemented as the shell script "wlanpoke.sh." plus supporting files and documentation. There is also an optional script simple 'web server' to serve statistics to a web browser.

This software has been rushed together in response to an emergency of constantly failing radios. Versions have been keeping the author's 4 SB and 3 UE radios connected for 6 months as of this writing. Several users have downloaded previous versions, and they have reported that it has generally worked to keep their radios usable. This software is just a temporary partial mitigation of a serious reliability issue that has arisen during 2020. There are many un- or under-tested functions and features, multitudes of bugs, questionable methods, and coding ugliness. Please assist in pointing these out or fixing them.

We hope this software will become obsolete when the root causes of the unreliability have been fixed. In the mean time, your kind suggestions and improvements are appreciated. Please feel free to modify and adapt the scripts for your own purposes. And please feel free to join the effort to find real lasting solutions to this issue.

Please address your responses to the slimdevices forums https://forums.slimdevices.com/showthread.php?109953-WiFi-connection-unstable-lost-on-three-Radios or https://forums.slimdevices.com/showthread.php?111663-Community-Build-Radio-Firmware

Note: the github download system creates a zip file containing a folder with the same name as the zip file name. This is no longer a flat file, and, when unzipped, deposits the software into a sub folder named for the version. The contents of this sub folder must be copied to the installation folder, which is a step that was not described in the original manual.txt instructions. New versions of this file, with higher minor numbers, are placed in the main branch as they are written, and may be helpful. Good luck!
