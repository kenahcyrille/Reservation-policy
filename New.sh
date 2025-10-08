UIDNUM=$(id -u)
GIDNUM=$(id -g)

sudo mkdir -p /tmp/ansible-local /tmp/ansible-remote
sudo chown $UIDNUM:$GIDNUM /tmp/ansible-local
sudo chmod 700 /tmp/ansible-local

sudo chown root:root /tmp/ansible-remote
sudo chmod 1777 /tmp/ansible-remote
