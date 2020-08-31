#!/bin/bash

#Inputüberprüfung einfügen
#Input1 = Clientanschluss
#Input2 = Serveranschluss
#Input3 = IP Client

if [ "$EUID" -ne 0 ]
	then echo "Please run as root"
	exit
fi

wronginput () {
	echo "You need at least 2 interfaces as input."
	echo "1st input = interface used for the client and creates DHCP-Server on this machine"
	echo "2nd input = interface used to forward to internet or server"
	echo "3rd input = optional input for naming the IP-address of DHCP on interface in 1st input, else it will be 192.168.3.1"
	echo "Example1: ./mitm-v0.1.sh eth1 eth2"
	echo "Example2: ./mitm-v0.1.sh eth1 eth2 192.168.3.1"
}

if [ -z $1 ]; then
	wronginput
	exit 0
fi

if [ -z $2 ]; then
	wronginput
	exit 0
fi

#ToDo: Den Input 1-3 jeweils als Variable abspeichern und darüber die Funktionen auslagern, bzw nicht mehr verschachtelt aufrufen, sondern einfach von oben nach unten durchgehen. Oder zumindest mit Variablen besser leserlich machen.

echo "This script sets up a MITM scenario."
echo " "

#ToDo: check if dnsmasq is installed
changednsmasq () {
#	$1 = client/dhcp-interface
#	$2 = server-interface
	echo "interface=$1                              ## define interface to listen to" > /etc/dnsmasq.conf
	echo "dhcp-range=192.168.3.3,192.168.3.3,12h    ## 12h is the Lease-Time" >> /etc/dnsmasq.conf
	echo "dhcp-option=3,$2                          ## set local IP as gateway for network" >> /etc/dnsmasq.conf

	service dnsmasq restart
}

setdnsandiptables () {
	#1 = client-interface
	#2 = client-ip
	
	#ToDo: check if nonempty
	kill $(ps aux | grep "mitm-while-ifconfig.run" | grep -v "grep\|nano\|vi\|gedit" | tr -s " " | cut -d " " -f2)

	echo "#!/bin/bash" > ~/mitm-while-ifconfig.run
	echo "while [ 0 ]; do ifconfig $1 192.168.3.1; sleep 1; done" >> ~/mitm-while-ifconfig.run
    chmod 755 ~/mitm-while-ifconfig.run
    ~/mitm-while-ifconfig.run &
	changednsmasq $1 $2
	sysctl -w net.ipv4.ip_forward=1
	iptables -F
}

setuppostrouting () {
#	$1 = server-interface
#	$2 = client-ip
	iptables -t nat -A POSTROUTING -o $1 -s $2/24 -j MASQUERADE
}

setupprerouting () {
#	$1 = client-interface
#	$2 = client-ip
	#ToDo: Schleife, sodass man automatisch den MITM über socat oder BURP portweise aufbauen kann. Erstmal nur TCP.
	
	# This is http and going through burp
	#ToDo: burp anfragen auf welchem port
	iptables -t nat -A PREROUTING -i $1 -s $2/24 -p tcp --dport 80 -j DNAT --to-destination $2:8080
	iptables -t nat -A PREROUTING -i $1 -s $2/24 -p tcp --dport 443 -j DNAT --to-destination $2:8080
	
	# This is some different protocol, use socat to at least read it.
	# ToDo: Generate a script, which can then use netsed to change traffic live on the fly
	#while (true); do
	#	read -p "Do you want to intercept some other traffic? (y/n)"
	#done
	
	#iptables -t nat -A PREROUTING -i $1 -s $2/24 -p tcp --dport 8999 -j DNAT --to-destination $2:8999
	#socat -v TCP-LISTEN:8999,reuseaddr,fork TCP:10.107.240.246:8999
}


checkburp () {
	echo "Please check the connection of the client now."
	read -p "Do you want to intercept with BURP (y/n)? If yes, please set BURP to listen as invisible proxy on ${2}:8080." -n 1 -r
	echo " "
	if [[ $REPLY =~ ^[Yy]$ ]]; then
		setupprerouting $1 $2
	fi
	echo " "
}

allsetup () {
	setdnsandiptables $1 $3
	setuppostrouting $2 $3
	
	checkburp $1 $3
}

if [ -z $3 ]; then
	allsetup $1 $2 192.168.3.1
else
	allsetup $1 $2 $3
fi



