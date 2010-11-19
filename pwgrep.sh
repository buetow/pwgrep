#!/bin/bash 

# pwgrep v0.8-pre-1 (c) 2009, 2010 by Paul Buetow
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
# For more reasonable commands the following symlinks are recommended.
# Take a look at the create-symlinks.sh script.	

# You can overwrite the default values by setting env. variables
# or by just editing this file.
DEFAULTPWGREPDB=mydb.gpg
[ -z "$PWGREPRC" ] && PWGREPRC=~/.pwgreprc

# Only use mawk or gawk, but if possible not nawk. On *BSD awk=nawk. So try 
# awk/nawk last. You can use nawk but nawk will not match case insensitive.
[ -z "$TRYAWKLIST" ] && TRYAWKLIST="mawk gawk awk nawk"
# Find the correct command to wipe temporaly files after usage
[ -z "$TRYWIPELIST" ] && TRYWIPELIST="destroy shred"
# Same for sed
[ -z "$TRYSEDLIST" ] && TRYSEDLIST="sed gsed"

# From here, do not change stuff! You may edit the content of the file $PWGREPRC!

function source_config () {
	if [ -f $PWGREPRC ]; then
		$SED 's/^/export /' $PWGREPRC > $PWGREPRC.source
		source $PWGREPRC.source && rm $PWGREPRC.source
	fi
}

function configure () {
   	# Reading the current configuration
   	source_config

	# Setting default values if not set in the configuration file already
	(
	[ -z "$SVN_EDITOR" ] && echo 'SVN_EDITOR="ex -c 1"'
	[ -z "$PWGREPDB" ] && echo PWGREPDB=$DEFAULTPWGREPDB

	# The PWGREPWORDIR should be in its own versioning repository. 
	# For password revisions.
	[ -z "$PWGREPWORKDIR" ] && echo PWGREPWORKDIR=~/svn/pwdb
	[ -z "$PWFILEDIREXT" ] && echo PWFILEDIREXT=files

	# Enter here your GnuPG key ID
	#[ -z "$GPGKEYID" ] && echo GPGKEYID=F4B6FFF0
	[ -z "$GPGKEYID" ] && echo GPGKEYID=37EC5C1D

	# Customizing the versioning commands (i.e. if you want to use another
	# versioning system).
	[ -z "$VERSIONCOMMIT" ] && echo 'VERSIONCOMMIT="svn commit"'
	[ -z "$VERSIONUPDATE" ] && echo 'VERSIONUPDATE="svn update"'
	[ -z "$VERSIONADD" ] && echo 'VERSIONADD="svn add"'
	[ -z "$VERSIONDEL" ] && echo 'VERSIONDEL="svn delete"'
	) >> $PWGREPRC

	# Re-reading the current configuration, because there might be new
	# variables by now
   	source_config
}


function out () {
	echo "$@" 1>&2
}

function info () {
	out "=====> $@" 
}

function error () {
	echo "ERROR: $@"
	exit 666	
}

function findbin () {
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

function setawkcmd () {
	AWK=$(findbin "$TRYAWKLIST")
	[ -z $AWK ] && error No awk found in $PATH
}

function setsedcmd () {
	SED=$(findbin "$TRYSEDLIST")
	[ -z $SED ] && error No sed found in $PATH
}

function setwipecmd () {
	WIPE=$(findbin "$TRYWIPELIST")

	if [ -z $WIPE ]; then
		# FreeBSDs rm includes -P which is secure enough
		if [ $(uname) = 'FreBSD' ]; then
			WIPE="rm -v -P"
		else
			error "No wipe command found in $PATH, please install shred or destroy"
		fi
	fi

	info Using $WIPE for secure file deletion
}

function pwgrep () {
	search=$1
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

function pwupdate () {
   if [ -z $NOVERSIONING ]; then
         info Updating repository
         $VERSIONUPDATE 2>&1 >/dev/null
   fi
}

function pwedit () {
	pwupdate
	cp -vp $PWGREPDB $PWGREPDB.$(date +'%s').snap && \
	gpg --decrypt $PWGREPDB > .database && \
	vim --cmd 'set noswapfile' --cmd 'set nobackup' \
		--cmd 'set nowritebackup' .database && \
	gpg --output .$PWGREPDB -e -r $GPGKEYID .database && \
	$WIPE .database && \
	mv .$PWGREPDB $PWGREPDB && \
	[ -z $NOVERSIONING ] && $VERSIONCOMMIT
}

function pwdbls () {
	echo Available Databases:
	ls *.gpg | sed 's/\.gpg$//'
	echo Current database: $PWGREPDB
}

function pwfls () {
	name=$(echo $1 | sed 's/.gpg$//')

	[ ! -e $PWFILEDIREXT ] && error $PWFILEDIREXT does not exist

	if [ -z $name ]; then
		ls $PWFILEDIREXT | sed -n '/.gpg$/ { s/.gpg$//; p; }' | sort 
		exit 0
	fi

	gpg --decrypt $PWFILEWORKDIR/${name}.gpg 
}

function pwfadd () {
	name=$(echo $1 | sed 's/.gpg$//')

	srcfile=$1
	if [ $(echo "$srcfile" | grep -v '^/') ]; then
		srcfile=$CWD/$srcfile	
	fi

	if [ ! -z $2 ]; then
		outfile=$(basename $2)
	else
		outfile=$(basename $name)
	fi

	pwupdate

	[ ! -e $PWFILEWORKDIR ] && error $PWFILEWORKDIR does not exist
	[ -z $name ] && error Missing argument 

	gpg --output $PWFILEDIREXT/${outfile}.gpg -e -r $GPGKEYID $srcfile && \

	if [ -z $NOVERSIONING ]; then
		$VERSIONADD $PWFILEDIREXT/${outfile}.gpg && $VERSIONCOMMIT
	fi
}

function pwfdel () {
	name=$(echo $1 | sed 's/.gpg$//')
	pwupdate

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

function pwhelp () {
	info Possible operations are:
cat <<END
      fwipe <FILE>            - Wiping a file
      pwdbls                  - Listing available DBs
      pwedit [OPTS]           - Editing current DB
      pwfadd                  - Adding a file to FDB
      pwfcat <NAME>           - Printing a file from FDB to stdout
      pwfdel <NAME>           - Deleting a file from FDB
      pwgrep [OPTS] <REGEX>   - Grepping current DB
      pwldb                   - Synonym for pwdbls
      pwupdate                - Updating FDB and all DBs
      pwhelp                  - Printing this help screen
Where OPTS are:
      -o                      - Offline mode
      -d <DB NAME>            - Using a specific DB
END
}

setawkcmd
setsedcmd
setwipecmd

configure

PWFILEWORKDIR=$PWGREPWORKDIR/$PWFILEDIREXT
CWD=$(pwd)
umask 177

cd $PWGREPWORKDIR || error "No such file or directory: $PWGREPWORKDIR"

BASENAME=$(basename $0)
ARGS=$@

function set_opts () {
	case $ARGS in 
	   -o*)
		# Offlinemode 
		NOVERSIONING=1
		ARGS=${ARGS[@]:2}
		set_opts
	   ;; 
	   -d*)
		# Alternate DB
		PWGREPDB=$(echo $ARGS | $AWK '{ print $2 }')
		ARGS=$(echo $ARGS | $SED "s/-d $PWGREPDB//")
		PWGREPDB=$PWGREPDB.gpg
		set_opts
	   ;;
	   *)
	esac
}

set_opts $ARGS

case $BASENAME in 
	pwgrep) 
		pwgrep $ARGS
	;;
	pwupdate) 
		pwupdate
	;;
	pwedit) 
		pwedit
	;;
	pwdbls) 
		pwdbls
      ;;
	pwldb) 
		pwdbls
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
      pwhelp
esac

