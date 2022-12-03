# wlanpoke
Mitigate Wireless Connectivity Loss in Squeezebox Radios

Version 0.8.5.5

Introduction

The wlanpoke software attempts to mitigate the "Wireless Connectivity Loss" issues suffered by the current version Squeezebox Baby radio software. The software periodically tests the wireless network, and if it fails for a while, restarts the wireless system without rebooting. The resulting network outage is under a minute, which may or may not interrupt music playback for a time or until resumed.

Connected ssh sessions frequently stay open during a restart.

The software sends failure incident report 'logs' to a computer running netcat (nc or ncat) as a server or a similar tcp logger. This computer should have enough disk space to accommodate log files. One or multiple servers on one or more machines can be used, and the software is configured to report to one of them.

Besides mitigating the wireless connectivity issue, the software instruments the radio's wireless behavior, and this data may be useful to developers troubleshooting the issues. However, you may not want that data collected and/or preserved. Fortunately, affirmative steps are required to setup and enable data logging. Also, the software has the option of disabling logging.

The software is implemented as the shell script "wlanpoke.sh." plus supporting files and documentation. There is also an optional script simple 'web server' to serve statistics to a web browser.

This software has been rushed together in response to an emergency of constantly failing radios. Versions have been keeping the author's 4 SB and 3 UE radios connected for 6 months as of this writing. Several users have downloaded previous versions, and they have reported that it has generally worked to keep their radios usable. This software is just a temporary partial mitigation of a serious reliability issue that has arisen during 2020. There are many un- or under-tested functions and features, multitudes of bugs, questionable methods, and coding ugliness. Please assist in pointing these out or fixing them.

We hope this software will become obsolete when the root causes of the unreliability have been fixed. In the mean time, your kind suggestions and improvements are appreciated. Please feel free to modify and adapt the scripts for your own purposes. And please feel free to join the effort to find real lasting solutions to this issue.

Please address your responses to the slimdevices forums  https://forums.slimdevices.com/showthread.php?109953-WiFi-connection-unstable-lost-on-three-Radios or https://forums.slimdevices.com/showthread.php?111663-Community-Build-Radio-Firmware

Use the latter for more technical questions and discussions.

NOTE: Experimental Failure Reduction

This version is an experimental release that incorporates a brute force application of an experimental method to reduce WLAN failure. Some portable or mobile functionality may be degraded. You may wish to revert your system to a previous version. Check for updates. Read history.txt. Please post your experiences on the Squeezebox Radio forum and the GitHub issues tab.

A possible cause for failure has been identified as too frequent scanning for alternate access points by the radio even when connected to a strong signal router or access point. This scanning may encounter signals or packets that cause the radio to lose wireless sensitivity, degrade reception, and eventually fail. This version includes a function to attempt to reduce the number of these scans. The function uses very poorly or undocumented calls to the radio's wireless driver and chip in the belief that this will have the desired effect. Testing over a few days suggests that this provides a dramatic improvement in some fixed location radios. Other fixed location radios show less improvement. However, other use cases, especially ones that require frequent switching wireless networks, may be degraded. 

The function is controlled by a small text file in the install directory (/etc/wlanpoke) named "scanctrl.inc." It contains at minimum 6 numbers that disable or enable various aspects of the radio's scan function under some circumstances. The default is a list of 6 zeros, to disable everything possible with this function. That may be too much for your use case.

If your experience is degraded, you may wish to disable this function altogether. To do so, overwrite any existing "scanctrl.inc." file with a short (< 11 character) message, e.g.,
  echo "stop" > scanctrl.inc
will do it. Or you can delete the file and then "touch scanctrl.inc" to create a zero length file. If you delete the file, it will be recreated with default values the next time wlanpoke launches.
You can experiment with the parameters on the fly, e.g., 
  echo "0 0 1 0 0 0" > scanctrl.inc			(a nonsense example)
They will be applied after the next quick or full reset. You can pore over the documentation by reading the script and entering /lib/atheros/wmiconfig to get its documentation as it were.

News:

Version 0.8.7.1 (experimental) see above.

Version 0.8.6 (unreleased) fixed a bug that crashed the script when an access point name contains an apostrophe

Version 0.8.5 enables the quick reset by default and improves the RawFails Resets report to show the effect of the quick reset more clearly.

Version 0.8.4 adds two measures of network outages. A Gaps report lists recent outages as gaps and connected times in real seconds. A Resets report similarly lists recent outages resulting in resets. A unix time stamp has been added to the launch time and some other messages, and is used to accurately calculate elapsed seconds. A bug that produced a mostly blank status web page and RawFails report has been fixed.

Version 0.8.3 includes a new function calculates a safe full reset hold time based upon the latest full reset result to better handle lengthy network outages. Timestamps are reported without the time zone (e.g., -0700) suffix, and with an underbar replacing the 'T'. The full reset no longer causes a wpa_cli changed PID report. A bug that caused an incorrect 0 full reset recovery result has been fixed. RawFails report and startup log entries now show the launch options.

Version 0.8.2 was a very large revision of the software to address issues with low signal levels in the presence of interference causing the radio's poor wireless reception, which resulted in long delays after a reset to reestablish a connection. The prior software's fixed trial limit before reset (6) would trigger another full reset before the connection could be reestablished. The limit is now specified in seconds (default 12) and increased in steps if a lower limit fails. The "failed pings" counter keeps incrementing for a better measurement of outage time. Additional logging has been added to evaluate the system's performance in new ways. In particular a new reset recovery by limit time report shows the last several recovery times after a full reset indexed by the reset limit. The software now handles switching between Ethernet and wireless connections: an Ethernet connection disables wireless resets, although ping failures are still monitored and logged. Other code changes include improved math calculations, and a start at more meaningful and conforming variable names.

The investigation into the root causes of the outages continues. The wireless monitoring utility wpa_cli is under suspician. Code has been added to test for its presense and to relaunch it if it is no longer running. This utility working is important to the quick reset method. The full reset method restarts the entire network stack, including wpa_cli, so it is not affected. You may wish to edit the ResetQuick function to add or remove commands as the investigation continues, or just disable it if it the script does not *always* work on your system. Starting in 0.7.6, the quick reset method is disabled by default.

Note: the GitHub download system creates a zip file containing a folder with the same name as the zip file name. This is no longer a flat file, and, when unzipped, deposits the software into a sub folder named for the version. The contents of this sub folder must be copied to the installation folder, which is a step that was not described in the original manual.txt instructions. New versions of this file, with higher minor numbers, are placed in the main branch as they are written, and may be helpful. Good luck!
