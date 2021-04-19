#!/Users/kroybal/homebrew/bin/bash
#===============================================================================
#
#          FILE: pguri2pgpass.bash
#
#         USAGE: ./pguri2pgpass.bash
#
#   DESCRIPTION:  Change a URI in the form of 
#       postgres://user:pw@host:port/db?options
#       to
#       host:port:user:database:pass 
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Kirk L. Roybal (DBRE), kirk@webfinish.com
#  ORGANIZATION: Private
#       CREATED: 04/19/2021 11:46:02
#      REVISION:  ---
#===============================================================================



ScriptVersion="1.0"

#===  FUNCTION  ================================================================
#         NAME:  usage
#  DESCRIPTION:  Display usage information.
#===============================================================================
function usage ()
{
	cat <<- EOT

  Usage :  ${0##/*/} [options] [--] 

    echo "postgres://this_guy:some_password@remote_host:5432/the_database" | pguri2pgpass.bash
    remote_host:5432:the_database:this_guy:some_password

  Options: 
  -f|file [name]  Take input from a file
  -h|help         Display this message
  -v|version      Display script version

	EOT
}    # ----------  end of function usage  ----------

#-----------------------------------------------------------------------
#  Handle command line arguments
#-----------------------------------------------------------------------
input='-'  # STDIN

while getopts ":f:hv" opt
do
  case $opt in

    f|file     )  input="$OPTARG";;

    h|help     )  usage; exit 0   ;;

    v|version  )  echo "$0 -- Version $ScriptVersion"; exit 0   ;;

    \? )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;

  esac    # --- end of case ---
done
shift $(($OPTIND-1))


cat $input | sed -e 's_postgres://\(.*\):\(.*\)@\(.*\):\(.*\)/\(.*\)_\3:\4:\5:\1:\2 _'
