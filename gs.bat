rem Windows script to quickly fetch failure status information from a list of radios running wlanpoke and ahttpd.sh server
for %%d in (Radio1 192.168.0.8 Radio3) do curl http://%%d:8080/RawFails
