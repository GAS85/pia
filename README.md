# PIA
## PIA Client installation on Ubuntu system with encrypted home folder (ecryptfs)

For an older clients, e.g. client 66 and there is no need to do something else except to move PIA to the new destination `/usr/local/bin/pia` instead of root folder to be more comply to the Linux Filesystem Hierarchy Standard. Please try this script and then run PIA as usual via green icon.
Make it executable by command:

    chmod +x pia_ecryptfs.sh

and run as root:

    sudo ./pia_ecryptfs.sh
