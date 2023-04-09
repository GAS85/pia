#!/bin/sh

if [ "$(id -u)" -ne 0 ]; then
	echo "This script needs to be run as root. Try again with 'sudo $0'"
	exit
fi

read -rp 'Please enter your Linux username: ' linux_username
user_dir=/home/$linux_username
mkdir /usr/local/bin/pia

#it is already owned by root, but aynway...
chown root:root /usr/local/bin/pia
echo "Moving PIA to a new destination"
mv "$user_dir/.pia_manager" /usr/local/bin/pia/.pia_manager
echo "Creating link"
ln -s /usr/local/bin/pia/.pia_manager/ "$user_dir/.pia_manager"

echo "Done!"
exit
