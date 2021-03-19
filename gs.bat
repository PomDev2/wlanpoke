rem Windows script to quickly fetch failure status information from a list of radios running wlanpoke and ahttpd.sh server
rem edit the script to replace names or ip addresses in () with your radios. 
rem Set your router to give the radios fixed ip addresses.
rem Your router or a hosts file on or computer can set up name (name to ip) service.
for %%d in (Radio1 192.168.0.8 Radio3) do curl http://%%d:8080/RawFails
