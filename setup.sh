#! /usr/bin/zsh -e

export needed_packages=(rsync containerd runc which)
export APP_DIR=./data/app
export CACHE_DIR=./data/cache/umec
export PKG_CACHE=./data/cache/pacman/pkg

setopt extendedglob

sudo modprobe tun
sudo systemctl start libvirtd.service
mkdir -p ./data/cache/umec

# Some compressed Archlinux packages have extension zst, some xz
# (#qN) makes the expression return empty if there are no matches

for i in $needed_packages; do
	if [[ -n $PKG_CACHE/$i*.pkg.tar.*(#qN) ]]; then
		print "Already have $i"
	else
		print "Downloading $i"
		sudo pacman --noconfirm -Sw $i --cachedir $PKG_CACHE
	fi
done


# sudo pacman -Sw rsync containerd runc which--cachedir data/cache/pacman/pkg


mkdir --parents --verbose $CACHE_DIR
mkdir --parents --verbose $APP_DIR 

fetch_command() {
	local command=$1
	local url=$2
	if ! [[ -n $CACHE_DIR/install_$command(#qN) ]] ; then
	    echo "Fetching $command installation script"
            curl -L $2 -o $CACHE_DIR/install_$command
	else
	    print "Already have $command"
	fi
       	chmod u+x $CACHE_DIR/install_$command
}

fetch_command k3s "https://get.k3s.io" 
fetch_command helm https://raw.githubusercontent.com/kubernetes/helm/master/scripts/get

