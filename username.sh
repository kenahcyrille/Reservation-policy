# user name
u=$(id -un)
# primary group name
g=$(id -gn)

sudo chown "$u":"$g" /tmp/ansible-local
sudo chown root:root /tmp/ansible-remote
sudo chmod 700 /tmp/ansible-local /tmp/ansible-remote
