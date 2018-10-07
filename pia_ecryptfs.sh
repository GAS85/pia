#!/bin/bash

if [ "$(whoami)" != "root" ]; then
	echo "This script needs to be run as root. Try again with 'sudo $0'"
	exit
fi

echo -n "Please enter your Linux username: "
read linux_username

mkdir /usr/local/bin/pia

#it is already owned by root, but aynway...
chown root:root /usr/local/bin/pia
echo "Moving PIA to a new destination"
mv /home/$linux_username/.pia_manager/ /usr/local/bin/pia/.pia_manager
echo "Creating link"
ln -s /usr/local/bin/pia/.pia_manager/ /home/$linux_usermane/.pia_manager

echo "Done!"
exit
