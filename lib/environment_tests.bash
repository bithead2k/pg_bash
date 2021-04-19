#!/bin/echo -e "Include in calling script with\n source environment_tests.bash"
#===============================================================================
#
#          FILE: environment_tests.bash
#
#         USAGE: ./environment_tests.bash
#
#   DESCRIPTION:   Various rationality test for the shell and PostgreSQL 
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Kirk L. Roybal (DBRE), kirk.roybal@doordash.com
#  ORGANIZATION: OmniTI/Credativ/Instaclustr/Doordash
#       CREATED: 04/05/2021 18:48:35
#      REVISION:  ---
#===============================================================================

function find_psql ()
{
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  find_psql
#   DESCRIPTION:  find the client binary somewhere on the system
#    PARAMETERS:  none
#       RETURNS:  fully qualified path to psql
#-------------------------------------------------------------------------------

    #see if pg_config is configured
    local pgc=$(which pg_config &> /dev/null) 
	[[ ! -z $pgc ]] || bindir=
	[[ ! -z $pgc ]] && bindir=$($pgc --bindir)
	[[ ! -z $bindir ]] || psql_bin=
	[[ ! -z $bindir ]] && psql_bin=$bindir/psql
	[[ -x $psql_bin ]] && {
        echo $psql_bin
        return 0
    }
    #if not, use the local path
	psql_bin=$(which psql 2>/dev/null)
    [[ -x "$psql_bin" ]] && {
        echo "$psql_bin"
        return 0
    }
    #if that fails, just go fishing
	[[ -x /usr/bin/psql ]] && {
        echo "/usr/bin/psql"
        return 0
    }
	[[ -x /usr/local/pgsql/bin/psql ]] && {
        echo "/usr/local/pgsql/bin/psql"
        return 0
    }
	[[ -x /opt/local/bin/psql ]] && {
        echo "/opt/local/bin/psql"
        return 0
    }

    return 1
}	# ----------  end of function find_psql  ----------

function find_timeout ()
{
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  find_timeout
#   DESCRIPTION:  get a timeout executable
#    PARAMETERS:  none
#       RETURNS:  qualified path to timeout
#-------------------------------------------------------------------------------

    local to=$(which timeout)
    [[ -x $to ]] && {
        echo "$to "
        return 0
    }
    [[ -x "/opt/local/bin/gtimeout" ]] && {
        echo "/opt/local/bin/gtimeout "
        return 0
    }
    return 1
}	# ----------  end of function find_timeout  ----------


function can_ssh {
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  can_ssh
#   DESCRIPTION:  make the simplest possible connection to a foreign system
#    PARAMETERS:  hostname
#       RETURNS:  0 on success
# See if we can connect at all.  Return 0 if we can.
#-------------------------------------------------------------------------------

    [[ -z ${1:-} ]] && return 1
    $SSH root@$1 exit >& /dev/null
}

function can_ping {
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  can_ping
#   DESCRIPTION:  check icmp for connectivity
#    PARAMETERS:  hostname
#       RETURNS:  0 on success
#-------------------------------------------------------------------------------

    [[ -z ${1:-} ]] && return 1
    ping -c2 -i 0.2 -W2 $1 >& /dev/null
}

function check_ping {

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  can_ping
#   DESCRIPTION:  check for ICMP response
#    PARAMETERS:  command to remotely invoke, hostname
#       RETURNS:  OK/WARNING
#-------------------------------------------------------------------------------
    local cmd=$1
    local hostname=$2

    $(can_ping $hostname) && {
        status_msg $cmd "Ping OK"
        return 0
    }
    status_msg $cmd "No ICMP Ping Response" || return
    echo "** WARNING ** No ping response from $hostname"
    maybe_exit

}

function can_pg_connect ()
{
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  can_pg_connect
#   DESCRIPTION:  can talk to postgres on port 5432
#    PARAMETERS:  hostname
#       RETURNS:  0 success/1 failure
#-------------------------------------------------------------------------------

    [[ $(echo 'SELECT 1' | psql_wrap) == "1" ]]  && return 0
    return 1
}	# ----------  end of function can_pg_connect

function table_exists()
{
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  table_exists
#   DESCRIPTION: check that a table exists in the current connection 
#    PARAMETERS:  host, db, user, table
#       RETURNS:  0 or 1 exit
#-------------------------------------------------------------------------------

    local l_relation=${1:-}
    local l_schemata=${2:-public}

    local l_sql="SELECT COALESCE((SELECT true FROM information_schema.tables
    WHERE table_name = '$l_relation' AND table_schema = '$l_schemata'),false);"

    [[ $(echo "${l_sql}" | psql_wrap) == "t" ]]  && return 0
    return 1
}

function table_oid()
{
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  table_oid
#   DESCRIPTION: get the oid of the table 
#    PARAMETERS:  host, db, user, table, namespace
#       RETURNS:  integer
#-------------------------------------------------------------------------------
    local l_relation=${1:-}
    local l_schemata=${2:=}
    local l_sql="SELECT c.oid FROM pg_catalog.pg_class c LEFT JOIN pg_catalog.pg_namespace n ON n.oid = c.relnamespace
WHERE c.relname OPERATOR(pg_catalog.~) '^($l_relation)$' COLLATE pg_catalog.default
AND n.nspname OPERATOR(pg_catalog.~) '^($l_schemata)$' COLLATE pg_catalog.default;"

    echo "${l_sql}" | psql_wrap

}

function psql_wrap () {

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  psql_wrap
#   DESCRIPTION: execute a query 
#    PARAMETERS:  host, db, user, port
#       RETURNS:  unadorned scalar values from PostgreSQL
#-------------------------------------------------------------------------------
    $PSQL -qtA

}

function schema_exists(){

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  schema_exists
#   DESCRIPTION: check to see that a namespace exists in the current connection 
#    PARAMETERS:  namespace name
#       RETURNS:  0/1
#-------------------------------------------------------------------------------
    local l_schemata=${1:-}

    local l_sql="SELECT COALESCE((SELECT true FROM pg_catalog.pg_namespace WHERE nspname='$l_schemata'),false);"

    [[ $(echo "${l_sql}" | psql_wrap) == "t" ]]  && return 0
    return 1

}

function get_columns() {

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  get_columns
#   DESCRIPTION: get a list of columns with datatypes from the catalog 
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------

    local l_schemata=${1:-}
    local l_tablename=${2:-}

    local l_sql="SELECT column_name, data_type FROM information_schema.columns WHERE table_schema='$l_schemata' and table_name='$l_tablename' ORDER BY column_name;"

    echo "$l_sql" | psql_wrap


}

function list_columns(){


#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  list_columns
#   DESCRIPTION: make a comma delimited list of columns for insertion 
#    PARAMETERS:  
#       RETURNS:  
#-------------------------------------------------------------------------------

    local l_schemata=${1:-}
    local l_tablename=${2:-}

    local l_sql="SELECT array_to_string(array(SELECT quote_ident(column_name) FROM information_schema.columns WHERE table_schema='$l_schemata' and table_name='$l_tablename'), ',');"

    echo "$l_sql" | psql_wrap

}

function pg_version() {

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  pg_version
#   DESCRIPTION: Get the server version 
#    PARAMETERS:  
#       RETURNS:  version number
#-------------------------------------------------------------------------------

    local l_sql='SELECT setting FROM pg_catalog.pg_settings WHERE name = $$server_version_num$$;'

    echo "$l_sql" | psql_wrap

}

function quote_ident() {

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  quote_ident
#   DESCRIPTION: Make sure all identifiers are SQL quoted strings 
#    PARAMETERS:  some name that might need quotes
#       RETURNS:  string with quotes as necessary
#-------------------------------------------------------------------------------
    local l_identifier=${1:-}
    
    local l_sql="SELECT quote_ident('$l_identifier');"

    echo "$l_sql" | psql_wrap
}


function create_table_from_table () {

#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  make_table_from_table
#   DESCRIPTION: Create a table using LIKE
#    PARAMETERS:  source table, target table,
#       RETURNS:  0 if table created, 3 if not
#-------------------------------------------------------------------------------
    local l_source_namespace=${1:-public}
    local l_source_table=${2:-}
    local l_target_namespace=${3:-public}
    local l_target_table=${4:-}

    local l_sql="CREATE TABLE $(quote_ident "$l_target_namespace").$(quote_ident "$l_target_table") (LIKE $(quote_ident "$l_source_namespace").$(quote_ident "$l_source_table") INCLUDING ALL);"

    echo "$l_sql" | psql_wrap
    return $?

}

