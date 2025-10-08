# capture your numeric IDs
UIDNUM=$(id -u)
GIDNUM=$(id -g)

# start clean
sudo rm -rf /tmp/ansible-local /tmp/ansible-remote

# create with proper owners/permissions in one go
sudo install -d -m 700  -o "$UIDNUM" -g "$GIDNUM" /tmp/ansible-local
sudo install -d -m 1777 -o root      -g root       /tmp/ansible-remote

# (SELinux) give /tmp type to the remote dir, then relabel
if command -v getenforce >/dev/null && [ "$(getenforce)" = "Enforcing" ]; then
  sudo semanage fcontext -a -t tmp_t '/tmp/ansible-remote(/.*)?' 2>/dev/null || true
  sudo restorecon -Rv /tmp/ansible-remote
fi

# sanity check
ls -ld /tmp/ansible-local /tmp/ansible-remote
# expect: drwx------ <you>:<yourgid> /tmp/ansible-local
#         drwxrwxrwt root:root       /tmp/ansible-remote   (note the 't' sticky bit)
