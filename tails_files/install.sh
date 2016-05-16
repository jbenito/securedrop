#!/bin/bash
# SecureDrop persistent setup script for Tails

set -e

# set paths and variables
amnesia_home=/home/amnesia
amnesia_persistent=$amnesia_home/Persistent
securedrop_dotfiles=$amnesia_persistent/.securedrop
torrc_additions=$securedrop_dotfiles/torrc_additions
securedrop_init_script=$securedrop_dotfiles/securedrop_init.py
tails_live_persistence=/live/persistence/TailsData_unlocked
tails_live_dotfiles=$tails_live_persistence/dotfiles
amnesia_desktop=$amnesia_home/Desktop
securedrop_ansible_base=$amnesia_persistent/securedrop/install_files/ansible-base
network_manager_dispatcher=/etc/NetworkManager/dispatcher.d
securedrop_ssh_aliases=false


function validate_tails_environment()
{
  # Ensure that initial expectations about the SecureDrop environment
  # are met. Error messages below explain each condition.
  if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 1>&2
    exit 1
  fi
  source /etc/os-release
  if [[ $TAILS_VERSION_ID =~ ^1\..* ]]; then
    echo "This script must be used on Tails version 2.x or greater." 1>&2
    exit 1
  fi
  if [ ! -d "$tails_live_persistence" ]; then
    echo "This script must be run on Tails with a persistent volume." 1>&2
    exit 1
  fi
  if [ ! -d "$securedrop_ansible_base" ]; then
    echo "This script must be run with SecureDrop's git repository cloned to 'securedrop' in your Persistent folder." 1>&2
    exit 1
  fi
}

validate_tails_environment

# detect whether admin or journalist
if [ -f $securedrop_ansible_base/app-document-aths ]; then
  ADMIN=true
else
  ADMIN=false
fi

mkdir -p $securedrop_dotfiles

# copy icon, launchers and scripts
cp -f securedrop_icon.png $securedrop_dotfiles
cp -f document.desktop $securedrop_dotfiles
cp -f source.desktop $securedrop_dotfiles
cp -f securedrop_init.py $securedrop_init_script

# Remove binary setuid wrapper from previous tails_files installation, if it exists
WRAPPER_BIN=$securedrop_dotfiles/securedrop_init
if [ -f $WRAPPER_BIN ]; then
    rm $WRAPPER_BIN
fi

if $ADMIN; then
  DOCUMENT=`cat $securedrop_ansible_base/app-document-aths | cut -d ' ' -f 2`
  SOURCE=`cat $securedrop_ansible_base/app-source-ths`
  APPSSH=`cat $securedrop_ansible_base/app-ssh-aths | cut -d ' ' -f 2`
  MONSSH=`cat $securedrop_ansible_base/mon-ssh-aths | cut -d ' ' -f 2`
  echo "# HidServAuth lines for SecureDrop's authenticated hidden services" | cat - $securedrop_ansible_base/app-ssh-aths $securedrop_ansible_base/mon-ssh-aths $securedrop_ansible_base/app-document-aths > $torrc_additions
  if [[ -d "$amnesia_home/.ssh" && ! -f "$amnesia_home/.ssh/config" ]]; then
    # create SSH host aliases and install them
    SSHUSER=$(zenity --entry --title="Admin SSH user" --window-icon=$securedrop_dotfiles/securedrop_icon.png --text="Enter your username on the App and Monitor server:")
    cat > $securedrop_dotfiles/ssh_config <<EOL
Host app
  Hostname $APPSSH
  User $SSHUSER
Host mon
  Hostname $MONSSH
  User $SSHUSER
EOL
    chown amnesia:amnesia $securedrop_dotfiles/ssh_config
    chmod 600 $securedrop_dotfiles/ssh_config
    cp -pf $securedrop_dotfiles/ssh_config $amnesia_home/.ssh/config
    securedrop_ssh_aliases=true
  fi
  # set ansible to auto-install
  if ! grep -q 'ansible' "$tails_live_persistence/live-additional-software.conf"; then
    echo "ansible" >> $tails_live_persistence/live-additional-software.conf
  fi
  # update ansible inventory with .onion hostnames
  if ! grep -v "^#.*onion" "$securedrop_ansible_base/inventory" | grep -q onion; then
    sed -i "s/app ansible_ssh_host=.* /app ansible_ssh_host=$APPSSH /" $securedrop_ansible_base/inventory
    sed -i "s/mon ansible_ssh_host=.* /mon ansible_ssh_host=$MONSSH /" $securedrop_ansible_base/inventory
  fi
else
  # prepare torrc_additions (journalist)
  cp -f torrc_additions $torrc_additions
fi

# set permissions
chmod 755 $securedrop_dotfiles
chown root:root $securedrop_init_script
chmod 700 $securedrop_init_script
chown root:root $torrc_additions
chmod 400 $torrc_additions

chown amnesia:amnesia $securedrop_dotfiles/securedrop_icon.png
chmod 600 $securedrop_dotfiles/securedrop_icon.png

# journalist workstation does not have the *-aths files created by the Ansible playbook, so we must prompt
# to get the interface .onion addresses to setup launchers, and for the HidServAuth info used by Tor
if ! $ADMIN; then
  REGEX="^(HidServAuth [a-z2-7]{16}\.onion [A-Za-z0-9+/.]{22})"
  while [[ ! "$HIDSERVAUTH" =~ $REGEX ]];
  do
    HIDSERVAUTH=$(zenity --entry --title="Hidden service authentication setup" --width=600 --window-icon=$securedrop_dotfiles/securedrop_icon.png --text="Enter the HidServAuth value to be added to /etc/tor/torrc:")
  done
  echo $HIDSERVAUTH >> $torrc_additions
  SRC=$(zenity --entry --title="Desktop shortcut setup" --window-icon=$securedrop_dotfiles/securedrop_icon.png --text="Enter the Source Interface's .onion address:")
  SOURCE="${SRC#http://}"
  DOCUMENT=`echo $HIDSERVAUTH | cut -d ' ' -f 2`
fi

# make the shortcuts
echo "Exec=/usr/local/bin/tor-browser $DOCUMENT" >> $securedrop_dotfiles/document.desktop
echo "Exec=/usr/local/bin/tor-browser $SOURCE" >> $securedrop_dotfiles/source.desktop

# copy launchers to desktop and Applications menu
cp -f $securedrop_dotfiles/document.desktop $amnesia_desktop
cp -f $securedrop_dotfiles/source.desktop $amnesia_desktop
cp -f $securedrop_dotfiles/document.desktop $amnesia_home/.local/share/applications
cp -f $securedrop_dotfiles/source.desktop $amnesia_home/.local/share/applications

# make it all persistent
sudo -u amnesia mkdir -p $tails_live_dotfiles/Desktop
sudo -u amnesia mkdir -p $tails_live_dotfiles/.local/share/applications
cp -f $securedrop_dotfiles/document.desktop $tails_live_dotfiles/Desktop
cp -f $securedrop_dotfiles/source.desktop $tails_live_dotfiles/Desktop
cp -f $securedrop_dotfiles/document.desktop $tails_live_dotfiles/.local/share/applications
cp -f $securedrop_dotfiles/source.desktop $tails_live_dotfiles/.local/share/applications

# set ownership and permissions
chown amnesia:amnesia $amnesia_desktop/document.desktop $amnesia_desktop/source.desktop \
  $tails_live_dotfiles/Desktop/document.desktop $tails_live_dotfiles/Desktop/source.desktop \
  $amnesia_home/.local/share/applications/document.desktop $amnesia_home/.local/share/applications/source.desktop \
  $tails_live_dotfiles/.local/share/applications/document.desktop $tails_live_dotfiles/.local/share/applications/source.desktop
chmod 700 $amnesia_desktop/document.desktop $amnesia_desktop/source.desktop \
  $tails_live_dotfiles/Desktop/document.desktop $tails_live_dotfiles/Desktop/source.desktop \
  $amnesia_home/.local/share/applications/document.desktop $amnesia_home/.local/share/applications/source.desktop \
  $tails_live_dotfiles/.local/share/applications/document.desktop $tails_live_dotfiles/.local/share/applications/source.desktop

# remove xsessionrc from 0.3.2 if present
XSESSION_RC=$tails_live_persistence/dotfiles/.xsessionrc
if [ -f $XSESSION_RC ]; then
  rm -f $XSESSION_RC > /dev/null 2>&1

  # Repair the torrc backup, which was probably busted due to the
  # race condition between .xsessionrc and
  # /etc/NetworkManager/dispatch.d/10-tor.sh This avoids breaking
  # Tor after this script is run.
  #
  # If the Sandbox directive is on in the torrc (now that the dust
  # has settled from any race condition shenanigans), *and* there is
  # no Sandbox directive already present in the backup of the
  # original, "unmodified-by-SecureDrop" copy of the torrc used by
  # securedrop_init, then port that Sandbox directive over to avoid
  # breaking Tor by changing the Sandbox directive while it's
  # running.
  if grep -q 'Sandbox 1' /etc/tor/torrc && ! grep -q 'Sandbox 1' /etc/tor/torrc.bak; then
    echo "Sandbox 1" >> /etc/tor/torrc.bak
  fi
fi

# Remove previous NetworkManager hook if present. The "99-" prefix
# caused the hook to run later than desired.
for d in $tails_live_persistence $securedrop_dotfiles $network_manager_dispatcher; do
  rm -f "$d/99-tor-reload.sh" > /dev/null 2>&1
done

# set up NetworkManager hook
if ! grep -q 'custom-nm-hooks' "$tails_live_persistence/persistence.conf"; then
  echo "/etc/NetworkManager/dispatcher.d	source=custom-nm-hooks,link" >> $tails_live_persistence/persistence.conf
fi
mkdir -p $tails_live_persistence/custom-nm-hooks
cp -f 65-configure-tor-for-securedrop.sh $tails_live_persistence/custom-nm-hooks
cp -f 65-configure-tor-for-securedrop.sh $network_manager_dispatcher
chown root:root $tails_live_persistence/custom-nm-hooks/65-configure-tor-for-securedrop.sh $network_manager_dispatcher/65-configure-tor-for-securedrop.sh
chmod 755 $tails_live_persistence/custom-nm-hooks/65-configure-tor-for-securedrop.sh $network_manager_dispatcher/65-configure-tor-for-securedrop.sh

# set torrc and reload Tor
/usr/bin/python $securedrop_dotfiles/securedrop_init.py

# finished
echo ""
echo "Successfully configured Tor and set up desktop bookmarks for SecureDrop!"
echo "You will see a notification appear in the top-right corner of your screen."
echo ""
echo "The Document Interface's Tor onion URL is: http://$DOCUMENT"
echo "The Source Interfaces's Tor onion URL is: http://$SOURCE"
if $ADMIN; then
  echo ""
  echo "The App Server's SSH hidden service address is:"
  echo $APPSSH
  echo "The Monitor Server's SSH hidden service address is:"
  echo $MONSSH
  if $securedrop_ssh_aliases; then
    echo ""
    echo "SSH aliases are set up. You can use them with 'ssh app' and 'ssh mon'"
  fi
fi
echo ""
exit 0
