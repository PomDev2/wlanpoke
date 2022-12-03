rem  Windows script to quickly fetch failure status information from a list of radios running wlanpoke -W low and ahttpd.sh server 
rem  Set your router to give the radios fixed ip addresses.
rem  Your router or a hosts file on yoor computer can set up name (name to ip) service if you want to use names.
rem  Edit this script to replace the names or ip addresses inside the parantheses () with those of your radios.
for %%d in (Radio1 192.168.0.8 Radio3) do curl http://%%d:8080/RawFails & echo -
