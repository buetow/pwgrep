#!/bin/bash

# pwgrep v0.2 (c) 2009 by Dipl.-Inform. (FH) Paul C. Buetow
# pwgrep helps you to manage all your passwords using GnuGP
# for encryption and a versioning system (subversion by default)
# for keeping track all changes of your password database. In
# combination to GnuPG you should use the versioning system in
# combination with SSL or SSH encryption.

# If you are using a *BSD, you may edit the shebang line.
#
# Usage: 
#  Searching for a database value: 
#	./pwgrep.sh searchstring 
#  Editing the database (same but without args): 
#	./pwgrep.sh 
# For more reasonable commands the following symlinks are recommended: 
#	ln -s ~/svn/pwgrep/pwgrep.sh ~/bin/pwgrep
#	ln -s ~/svn/pwgrep/pwgrep.sh ~/bin/pwedit

# You can overwrite the default values by setting env. variables
# or by just editing this file.

[ -z $PWGREPDB] && PWGREPDB=database.gpg
[ -z $PWGREPWORKDIR ] && PWGREPWORKDIR=~/svn/pwgrep

[ -z $GPGKEYID ] && GPGKEYID=F4B6FFF0
[ -z $VERSIONCOMMIT ] && VERSIONCOMMIT="svn commit"
[ -z $VERSIONUPDATE ] && VERSIONUPDATE="svn update"

# Only use mawk or gawk, but if possible not nawk. On *BSD awk=nawk. So try 
# awk/nawk last. You can use nawk but nawk will not match case insensitive.
[ -z $TRYAWKLIST ] && TRYAWKLIST="mawk gawk awk nawk"

# Find the correct command to wipe temporaly files after usage
[ -z $TRYWIPELIST ] && TRYWIPELIST="destroy shred"

# Default perms. for new files is 600
umask 177

function info {
	echo "=====> $@"
}

function error {
	echo "ERROR: $@"
	exit 666	
}

function findbin {
	trylist=$1
	found=""
	for bin in $trylist; do
		if [ -z $found ]; then
			which=$(which $bin)
			[ ! -z $which ] && found=$bin	
		fi
	done

	echo $found
}

function setawkcmd {
	AWK=`findbin "$TRYAWKLIST"`
	[ -z $AWK ] && error No awk found in $PATH
	info Using $AWK
}

function setwipecmd {
	WIPE=`findbin "$TRYWIPELIST"`

	if [ -z $WIPE ]; then
		# FreeBSDs rm includes -P which is secure enough
		if [ `uname` = 'FreBSD' ]; then
			WIPE="rm -v -P"
		else
			error "No wipe command found in $PATH, please install shred or destroy"
		fi
	fi

	info Using $WIPE
}

function pwgrep () {
	search=$1
	$VERSIONUPDATE
	info Searching for $search

	gpg --decrypt $PWGREPDB | $AWK -v search="$search" '
		BEGIN { 
			flag=0 
			IGNORECASE=1
		} 
		!/^\t/ { 
			if (!flag && $0 ~ search) {
				flag=1
				print $0
			} else if (flag && $0 ~ search) {
				print $0
			} else if (flag) {
				flag=0
			}
		} /^\t/ && flag { 
			print $0 
		}' 
}

function pwedit () {
	cd $PWGREPWORKDIR || exit 1 
	$VERSIONUPDATE
	cp -vp $PWGREPDB $PWGREPDB.`date +'%s'`.snap && \
	gpg --decrypt $PWGREPDB > .database && \
	vim --cmd 'set noswapfile' --cmd 'set nobackup' \
		--cmd 'set nowritebackup' .database && \
	gpg --output .database.gpg -e -r $GPGKEYID .database && \
	$WIPE .database && \
	mv .database.gpg $PWGREPDB && \
	[ -z $DONOTUSEVERSIONING ] && $VERSIONCOMMIT
}

setawkcmd
setwipecmd

# Edit the database file if no argument is given
if [ -z $1 ]; then
	pwedit
else # Otherwise just grep the database
	pwgrep $1
fi
