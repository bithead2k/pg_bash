#===============================================================================
#
#          FILE: pgpass2uri.bash
#
#         USAGE: ./pgpass2uri.bash
#
#   DESCRIPTION: convert an entry in .pgpass to a URI
#       echo "host:port:db:user:pass" | ./pgpass2uri.bash
#           postgres://user:pass@host:port/db
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Kirk L. Roybal (DBRE), Kirk@webfinish.com
#  ORGANIZATION: Private
#       CREATED: 04/19/2021 02:00:00 PM
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

  echo "host:port:db:user:pass" | ./${0##/*/}
  postgres://user:pass@host:port/db

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

    f|file     ) input="$OPTARG";;

    h|help     )  usage; exit 0   ;;

    v|version  )  echo "$0 -- Version $ScriptVersion"; exit 0   ;;

    \? )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;

  esac    # --- end of case ---
done
shift $(($OPTIND-1))

cat $input | sed -e 's_^\(.*\):\(.*\):\(.*\):\(.*\):\(.*\)$_postgres://\4:\5@\1:\2/\3_'
