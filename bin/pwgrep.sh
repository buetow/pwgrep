#!/bin/bash

# pwgrep (c) 2009, 2010, 2011, 2013 by Paul Buetow
# pwgrep helps you to manage all your passwords using GnuGP
# for encryption and a versioning system (Git by default)
# for keeping track all changes of your password database. In
# combination to GnuPG you should use the versioning system in
# combination with SSL or SSH encryption.

# If you are using a *BSD, you may want to edit the shebang line.
#
# Usage: 
#
#  Searching for a database value: 
#  ./pwgrep.sh searchstring 
#
#  Editing the database (same but without args): 
#  ./pwgrep.sh 
#
# For more reasonable commands the following symlinks are recommended.
# Take a look at the create-symlinks.sh script.  

# You can overwrite the default values by setting env. variables
# or by just editing this file.
declare DEFAULTDB=private.gpg
declare DEFAULTFILESTOREDIR=filestore
declare DEFAULTFILESTORECATEGORY=default
declare DEFAULTSNAPSHOTDIR=~/.pwgrep.snapshots
declare -r PWGREP_VERSION=0.9.3

[ -z "$RCFILE" ] && RCFILE=~/.pwgreprc

# Only use mawk or gawk, but if possible not nawk. On *BSD awk=nawk. So try 
# awk/nawk last. You can use nawk but nawk will not match case insensitive.
[ -z "$TRYAWKLIST" ] && TRYAWKLIST="mawk gawk awk nawk"
# Find the correct command to wipe temporaly files after usage
[ -z "$TRYWIPELIST" ] && TRYWIPELIST="destroy shred"
# Same for sed
[ -z "$TRYSEDLIST" ] && TRYSEDLIST="sed gsed"

# From here, do not change stuff! You may edit the content of the file $RCFILE!

function source_config () {
  [ -f $RCFILE ] && source <($SED 's/^/export /' $RCFILE)
}


function configure () {
  # Reading the current configuration
  source_config

  # Setting default values if not set in the configuration file already
  (
  #[ -z "$SVN_EDITOR" ] && echo 'export SVN_EDITOR="ex -c 1"'
  [ -z "$GIT_EDITOR" ] && echo 'export GIT_EDITOR=vim'
  [ -z "$DB" ] && echo DB=$DEFAULTDB
  [ -z "$FILESTOREDIR" ] && echo export FILESTOREDIR=$DEFAULTFILESTOREDIR
  [ -z "$FILESTORECATEGORY" ] && echo export FILESTORECATEGORY=$DEFAULTFILESTORECATEGORY

  # The PWGREPWORDIR should be in its own versioning repository. 
  # For password revisions.
  [ -z "$WORKDIR" ] && echo export WORKDIR=~/git/pwdb

  # The dir there to store offline snapshots, which are something like backups 
  [ -z "$SNAPSHOTDIR" ] && echo export SNAPSHOTDIR=$DEFAULTSNAPSHOTDIR

  # Enter here your GnuPG key ID
  [ -z "$GPGKEYID" ] && echo export GPGKEYID=37EC5C1D

  # Customizing the versioning commands (i.e. if you want to use another
  # versioning system).
  [ -z "$VERSIONCOMMIT" ] && echo 'export VERSIONCOMMIT="git commit -a"'
  [ -z "$VERSIONUPDATE" ] && echo 'export VERSIONUPDATE="git pull origin master"'
  [ -z "$VERSIONPUSH" ] && echo 'export VERSIONPUSH="git push origin master"'
  [ -z "$VERSIONADD" ] && echo 'export VERSIONADD="git add"'
  [ -z "$VERSIONDEL" ] && echo 'export VERSIONDEL="git rm"'
  ) >> $RCFILE

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
  local -r trylist=$1
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
  local -r search=$1
  local -a dbs=()

  if [ -z "$ALL" ]; then
    dbs=$DB
  else
    dbs=$(_pwdbls | sed 's/$/.gpg/')
  fi

  for db in $dbs; do  
    info Searching for $search in $db
    gpg --use-agent --decrypt $db | $AWK -v search="$search" '
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
  done
}

function pwupdate () {
  if [ -z "$NOVERSIONING" ]; then
    info Updating repository
    $VERSIONUPDATE 2>&1 >/dev/null
  fi
}

function pwedit () {
  pwupdate
  test ! -d $SNAPSHOTDIR && mkdir -p $SNAPSHOTDIR && chmod 0700 $SNAPSHOTDIR
  cp -vp $DB $SNAPSHOTDIR/$DB.$(date +'%s').snap && \
  gpg --decrypt $DB > .database && \
  vim --cmd 'set noswapfile' --cmd 'set nobackup' \
    --cmd 'set nowritebackup' .database && \
  gpg --output .$DB -e -r $GPGKEYID .database && \
  $WIPE .database && \
  mv .$DB $DB && \
  [ -z "$NOVERSIONING" ] && $VERSIONCOMMIT && [ ! -z "$VERSIONPUSH" ] && $VERSIONPUSH
}

function _pwdbls () {
  ls *.gpg | sed 's/\.gpg$//'
}

function pwdbls () {
  echo Available Databases:
  _pwdbls
  echo Current database: $DB
}

function pwfls () {
  local arg=$1
  
  if [ "$ALL" = "1" ]; then
    ALL=0
    local -r dir=$WORKDIR/$FILESTOREDIR
    [ ! -e $dir ] && error $dir does not exist
  
    info Showing all categories
    ls $dir | while read store; do
      pwfls $store 
    done
  else
    local dir=$WORKDIR/$FILESTOREDIR

    if [ -z "$USEFILESTORECATEGORY" ]; then
      info Available file store categories:
      dir=$WORKDIR/$FILESTOREDIR
      info "(You may use '`basename $0` -d <CATEGORY>' to display containing files.)"
    else
      info Available files in store $FILESTORECATEGORY
      dir=$WORKDIR/$FILESTOREDIR/$FILESTORECATEGORY
    fi

    [ ! -e $dir ] && error "Category ($dir) does not exist"
      ls $dir 
  fi
}

function pwfcat () {
  local arg=$1
  
  if [ -z "$arg" ]; then
    error "No file specified (hint: use pwfls)"
  
  else
    local -r dir=$WORKDIR/$FILESTOREDIR/$FILESTORECATEGORY
    local -r file=$(echo $arg | sed 's/.gpg$//')
  
    [ ! -e $dir ] && error "Category $FILESTORECATEGORY ($dir) does not exist"
    [ ! -e $dir/$file.gpg ] && error "File $file in category $FILESTORECATEGORY does not exist"
    gpg --decrypt $dir/$file.gpg 
  fi
}

function pwfadd () {
  local -r name=$(echo $1 | sed 's/.gpg$//')
  local srcfile=$1
  local outfile=''

  if [ $(echo "$srcfile" | grep -v '^/') ]; then
    srcfile=$CWD/$srcfile  
  fi

  if [ ! -z $2 ]; then
    outfile=$(basename $2)
  else
    outfile=$(basename $name)
  fi

  pwupdate

  [ -z "$name" ] && error Missing argument 
    if [ ! -e $FULLFILESTORE ]; then
      info Creating new category
      [ ! -z "$NOVERSIONING" ] && error Cannot add new category with versioning disabled
      local -r umaskbackup=$(umask)
      umask 0022
      mkdir $FULLFILESTORE && $VERSIONADD $FULLFILESTORE && $VERSIONCOMMIT && [ ! -z "$VERSIONPUSH" ] && $VERSIONPUSH

      umask $umaskbackup
    fi

  [ ! -e $FILESTOREWORKDIR ] && error $FILESTOREWORKDIR does not exist
  gpg --output $FULLFILESTORE/$outfile.gpg -e -r $GPGKEYID $srcfile && \

  if [ -z "$NOVERSIONING" ]; then
    $VERSIONADD $FULLFILESTORE/$outfile.gpg && $VERSIONCOMMIT && [ ! -z "$VERSIONPUSH" ] && $VERSIONPUSH

  fi
}

function pwfdel () {
  local arg=$1
  
  if [ -z "$arg" ]; then
    error "No file specified (hint: use pwfls)"
  
  else
    local -r dir=$WORKDIR/$FILESTOREDIR/$FILESTORECATEGORY
    local -r file=$(echo $arg | sed 's/.gpg$//')
    local -r filepath=$dir/$file.gpg
  
    [ ! -e $dir ] && error "Category $FILESTORECATEGORY ($dir) does not exist"
    [ ! -e $filepath ] && error "File $file in category $FILESTORECATEGORY does not exist"
  
    if [ -z "$NOVERSIONING" ]; then
      # Wipe even encrypted file securely
      $WIPE $filepath && \
      touch $filepath && $VERSIONCOMMIT && \
      $VERSIONDEL $filepath && $VERSIONCOMMIT
      [ ! -z "$VERSIONPUSH" ] && $VERSIONPUSH
    else
      $WIPE $filepath
    fi
  fi
}

function fwipe () {
  [ -z $1 ] && error Missing argument
  $WIPE $CWD/$1
}

function pwhelp () {
  info $PWGREP_VERSION
  info Possible operations are:
cat <<END
  fwipe <FILE>            - Wiping a file
  pwdbls                  - Listing available DBs
  pwedit [OPTS]           - Editing current DB
  pwfadd <FILE>           - Adding a file to FDB
  pwfcat <NAME>           - Printing a file from filestore to stdout
  pwfdel <NAME>           - Deleting a file from filestore
  pwgrep [OPTS] <REGEX>   - Grepping current DB
  pwldb                   - Synonym for pwdbls
  pwupdate                - Updating FDB and all DBs
  pwhelp                  - Printing this help screen
Where OPTS are:
  -o                      - Offline mode
  -d <DB NAME>            - Using a specific DB
  -a                 - Searching all available DBs or categories at once
END
}

setawkcmd
setsedcmd
setwipecmd

configure

CWD=$(pwd)
#umask 177

cd $WORKDIR || error "No such file or directory: $WORKDIR"

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
      DB=$(echo $ARGS | $AWK '{ print $2 }')
                  FILESTORECATEGORY=$DB
      USEFILESTORECATEGORY=1
      ARGS=$(echo $ARGS | $SED "s/-d $DB//")
      DB=$DB.gpg
      set_opts
     ;;

     -a*)
      # All DBs at once
      which gpg-agent  
      if [ $? == "0" ]; then   
        ALL=1
        ARGS=${ARGS[@]:2}
        set_opts
      else
        error You need gpg-agent installed    
      fi
     ;;

     *)
  esac
}

set_opts $ARGS
FULLFILESTORE=$FILESTOREDIR/$FILESTORECATEGORY
FILESTOREWORKDIR=$WORKDIR/$FULLFILESTORE

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
    pwfcat $ARGS
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
  ;;
esac

