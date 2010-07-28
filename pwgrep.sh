#!/bin/bash 

# pwgrep v0.5.1 (c) 2009, 2010 by Paul C. Buetow
# pwgrep helps you to manage all your passwords using GnuGP
# for encryption and a versioning system (subversion by default)
# for keeping track all changes of your password database. In
# combination to GnuPG you should use the versioning system in
# combination with SSL or SSH encryption.

# If you are using a *BSD, you may want to edit the shebang line.
#
# Usage: 
#
#  Searching for a database value: 
#	./pwgrep.sh searchstring 
#
#  Editing the database (same but without args): 
#	./pwgrep.sh 
#
# For more reasonable commands the following symlinks are recommended: 
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/pwgrep
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/pwedit
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/pwfls
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/pwfcat
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/pwfadd
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/pwfdel
#	ln -s ~/svn/pwgrep/v?.?/pwgrep.sh ~/bin/fwipe
# Replace ?.? with the version of pwgrep you want to use. Your PATH variable 
# should also include ~/bin then.

# You can overwrite the default values by setting env. variables
# or by just editing this file.

[ -z $SVN_EDITOR ] && SVN_EDITOR=ex
[ -z $PWGREPDB ] && PWGREPDB=database.gpg

# The PWGREPWORDIR should be in its own versioning repository. 
# For password revisions.
[ -z $PWGREPWORKDIR ] && PWGREPWORKDIR=~/svn/pwdb
[ -z $PWFILEDIREXT ] && PWFILEDIREXT=files

# Enter here your GnuPG key ID
#[ -z $GPGKEYID ] && GPGKEYID=F4B6FFF0
[ -z $GPGKEYID ] && GPGKEYID=37EC5C1D

# Customizing the versioning commands (i.e. if you want to use another
# versioning system).
[ -z $VERSIONCOMMIT ] && VERSIONCOMMIT="svn commit"
[ -z $VERSIONUPDATE ] && VERSIONUPDATE="svn update"
[ -z $VERSIONADD ] && VERSIONADD="svn add"
[ -z $VERSIONDEL ] && VERSIONDEL="svn delete"

# Only use mawk or gawk, but if possible not nawk. On *BSD awk=nawk. So try 
# awk/nawk last. You can use nawk but nawk will not match case insensitive.
[ -z $TRYAWKLIST ] && TRYAWKLIST="mawk gawk awk nawk"

# Find the correct command to wipe temporaly files after usage
[ -z $TRYWIPELIST ] && TRYWIPELIST="destroy shred"

# From here, do not change stuff!

PWFILEWORKDIR=$PWGREPWORKDIR/$PWFILEDIREXT
CWD=`pwd`
umask 177

cd $PWGREPWORKDIR || error "No such file or directory: $PWGREPWORKDIR"

function out {
	echo "$@" 1>&2
}

function info {
	out "=====> $@" 
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
	[ -z $NOVERSIONING ] && $VERSIONUPDATE 2>&1 >/dev/null
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
	[ -z $NOVERSIONING ] && $VERSIONUPDATE 2>&1 >/dev/null
	cp -vp $PWGREPDB $PWGREPDB.`date +'%s'`.snap && \
	gpg --decrypt $PWGREPDB > .database && \
	vim --cmd 'set noswapfile' --cmd 'set nobackup' \
		--cmd 'set nowritebackup' .database && \
	gpg --output .database.gpg -e -r $GPGKEYID .database && \
	$WIPE .database && \
	mv .database.gpg $PWGREPDB && \
	[ -z $NOVERSIONING ] && $VERSIONCOMMIT
}

function pwfls () {
	name=`echo $1 | sed 's/.gpg$//'`
	[ -z $NOVERSIONING ] && $VERSIONUPDATE 2>&1 >/dev/null

	[ ! -e $PWFILEDIREXT ] && error $PWFILEDIREXT does not exist

	if [ -z $name ]; then
		ls $PWFILEDIREXT | sed -n '/.gpg$/ { s/.gpg$//; p; }' | sort 
		exit 0
	fi

	gpg --decrypt $PWFILEWORKDIR/${name}.gpg 
}

function pwfadd () {
	name=`echo $1 | sed 's/.gpg$//'`

	srcfile=$1
	if [ `echo "$srcfile" | grep -v '^/'` ]; then
		srcfile=$CWD/$srcfile	
	fi

	if [ ! -z $2 ]; then
		outfile=`basename $2`
	else
		outfile=`basename $name`
	fi

	[ -z $NOVERSIONING ] && $VERSIONUPDATE 2>&1 >/dev/null


	[ ! -e $PWFILEWORKDIR ] && error $PWFILEWORKDIR does not exist
	[ -z $name ] && error Missing argument 

	gpg --output $PWFILEDIREXT/${outfile}.gpg -e -r $GPGKEYID $srcfile && \

	if [ -z $NOVERSIONING ]; then
		$VERSIONADD $PWFILEDIREXT/${outfile}.gpg && $VERSIONCOMMIT
	fi
}

function pwfdel () {
	name=`echo $1 | sed 's/.gpg$//'`
	[ -z $NOVERSIONING ] && $VERSIONUPDATE 2>&1 >/dev/null


	[ ! -e $PWFILEWORKDIR ] && error $PWFILEWORKDIR does not exist
	[ -z $name ] && error Missing argument 

	if [ -z $NOVERSIONING ]; then
		# Wipe even encrypted file securely
		$WIPE $PWFILEDIREXT/${name}.gpg && \
		touch $PWFILEDIREXT/${name}.gpg && $VERSIONCOMMIT && \
		$VERSIONDEL $PWFILEDIREXT/${name}.gpg && $VERSIONCOMMIT
	else
		$WIPE $PWFILEDIREXT/${name}.gpg
	fi
}

function fwipe () {
	[ -z $1 ] && error Missing argument
	$WIPE $CWD/$1
}

setawkcmd
setwipecmd

BASENAME=`basename $0`
ARGS=$@

case $1 in 
   -o)
      # Offlinemode 
      NOVERSIONING=1
      ARGS=${ARGS[@]:2}
   ;;
   *)
esac

case $BASENAME in 
	pwgrep) 
		pwgrep $ARGS
	;;
	pwedit) 
		pwedit
	;;
	pwfls) 
		pwfls $ARGS
	;;
	pwfcat) 
		pwfls $ARGS
	;;
	pwfadd) 
		pwfadd $ARGS
	;;
	pwfdel) 
		pwfdel $ARGS
	;;
	fwipe) 
		fwipe $ARGS
	;;
	*)
	error No such operation $basename
esac

