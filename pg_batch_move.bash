#!/bin/bash -l
#  must be login interactive to load the global /etc/paths/ /etc/paths.d/*
#===============================================================================
#
#          FILE: pg_batch_move.bash
#
#         USAGE: ./pg_batch_move.bash
#
#      Usually, that will look something like this:
#      ./pg_batch_move.bash -s source_table -t target_table -l -c "created_at <= (now() - '90 days'::interval)::date" -b 100000
#
#   DESCRIPTION: Move tuples from one relation to another in groups
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: Licensed under the PostgreSQL license.
#        AUTHOR: Kirk L. Roybal (DBRE), kirk.roybal@doordash.com
#  ORGANIZATION: OmniTI/Credativ/Instaclustr/Doordash
#       CREATED: 04/05/2021 17:31:59
#      REVISION:  ---
#===============================================================================

function die() {
	
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  die
#   DESCRIPTION: Diplay an error message and commit sepuku 
#    PARAMETERS:  return value + message
#       RETURNS:  exits
#-------------------------------------------------------------------------------

	retval=$1
	shift
	echo -e "$@"
	exit $retval

}

# nounset vars, last pipe exit status
set -uo pipefail

# Set up the environment first.
# Source the testing engine.
whereami=$(dirname $(readlink -f "$0"))

[[ -f "$whereami/lib/assertion_engine.bash" ]] && source "$whereami/lib/assertion_engine.bash" || die 1 "Could not load required libraries for assertion."
[[ -f "$whereami/lib/environment_tests.bash" ]] && source "$whereami/lib/environment_tests.bash" || die 1 "Could not load fuctions to test conditions."
[[ -f "$whereami/lib/pg_license.bash" ]] && source "$whereami/lib/pg_license.bash"

# for some stupid f* reason, macOS quit sourcing /etc/paths.d in subshells.
case $OSTYPE in
	"linux-gnu"*) ;; 
	"darwin"*) # force the damn paths to load
	       	eval `/usr/libexec/path_helper -s` ;;
	"cygwin") ;; 
        # POSIX compatibility layer and Linux environment emulation for Windows
	"msys") ;; 
        # Lightweight shell and GNU utilities compiled for Windows (part of MinGW)
	"win32") ;; # I'm not sure this can happen.
	"$freebsd"*) ;;
	*) ;;
esac

# Global variables
ScriptVersion="1.0"
batch_percent=0
batch_size=1000
cleanup=0
column_list=
database=
generate=false
hostname=socket
hostport=
hostuser=
interval=0
make_target=false
min_pg_version=90300
pg_version=
qualifications=
runtime=0
script_name=
show_pgversion=0
show_version=false
source_relation=
source_schema=public
ssh_tunnel=
statement_timeout=3
target_relation=
target_schema=public
verbosity=0

function usage ()
{
#===  FUNCTION  ================================================================
#         NAME:  usage
#  DESCRIPTION:  Display usage information.
#===============================================================================
	cat <<- EOT

  Move rows from one table to another table in transacted batches.

  Usage :  ${0##/*/} [options] -s relation1 -t relation2 -c "quals" [--] 
  
  For example:  
  ${0##/*/} -s source_table -t target_table -l -c "created_at <= (now() - '90 days'::interval)::date" -b 100000

  Options: 
  -b|batch     [rows]       Number of rows to move per batch. Default $batch_size
  -c|criteria  [text]       Additional to WHERE clause.  Default empty
  -C|cleanup   [value]      1 = VACUUM, 2 = ANALYZE, 3 = VACUUM ANALYZE.  Default: 0 = Nothing.
  -d|database  [name]       Specifies database name to connect to.
  -f|fields    [list]       Comma delimited list of fields to move.  Default: Use the source relation.
  -g|generate  [script]     Generate a script that does the work.
  -h|host      [name]       Specifies the host name of the machine on which the server is running.  Default: unix socket
  -i|interval  [seconds]    Number of seconds to wait between batches.  Default: 0.
  -l|log                    Cumulative logging flag.  (e.g. -lll).  Sets the verbosity of the output.  Default: quiet.
  -m|make                   Create the destination table based on the source table.  Default: off.
  -P|percent   [int]        Percentage of rows to move compared to total initial candidates. Default: 100
  -r|runtime   [seconds]    Timeout of total operation. Default: infinite
  -s|source    [table]      Table to move rows from.  Required.
  -S|ssh       [command]    Prefix SSH tunnel command to psql.
  -n|namespace [schema]     Schema of the relations.  Default: $source_schema
  -t|target    [table]      Table to move rows to.    Required.
  -u|U|user    [name]       Name of PostgreSQL user.  Default: $USER
  -v|version                Display script version.
  -V|pgversion              Display the version of PostgreSQL on the host.
  -w|wait      [seconds]    psql statement timeout.  Default: 3 seconds.  0=disabled

Supports libpq style authentication, including .pgpass.

	EOT

}    # ----------  end of function usage  ----------

#-----------------------------------------------------------------------
#  Handle command line arguments
#-----------------------------------------------------------------------
# If there aren't any, show usage
[[ $# -gt 0 ]] || { usage; exit 0; }

while getopts ":b:c:d:C:f:g:h:i:lmn:p:P:r:s:S:t:u:U:vVw:" opt
do
  case $opt in

    b|batch    )  batch_size=$OPTARG ;;

    c|criteria )  qualifications="$OPTARG";;

    C|cleanup  )  cleanup=$OPTARG;;

    d|database )  database="$OPTARG";;

    f|fields   )  column_list="$OPTARG";;

    g|generate )  generate="true"; script_name="$OPTARG";;

    h|host     )  hostname="$OPTARG";;

    i|interval ) interval=$OPTARG;;

    l|log      )  (( verbosity++ ));;

    m|make     )  make_target="true";;

    n|namespace)  source_schema="$OPTARG"; target_schema="$OPTARG";;

    p|port     )  hostport=$OPTARG;;

    P|percent  )  batch_percent=$OPTARG;;

    r|runtime  )  runtime=$OPTARG;;

    s|source   )  source_relation="$OPTARG";;

    S|ssh      )  ssh_tunnel="$OPTARG";;

    t|target   )  target_relation="$OPTARG";;

    u|user     )  hostuser="$OPTARG";;

    U          )  hostuser="$OPTARG";;

    v|version  )  echo "$0 -- Version $ScriptVersion"; display_license; exit 0   ;;

    V|pgversion)  show_version=true;;

    w|wait     )  statement_timeout=$OPTARG;;

    \? )  echo -e "\n  Option does not exist : $OPTARG\n"
          usage; exit 1   ;;

  esac    # --- end of case ---
done
shift $(($OPTIND-1))

# set verbose or debug depending on verbosity
[[ $verbosity -gt 2 ]] && set -v
[[ $verbosity -gt 3 ]] && set -x

# Test the engine

[[ $verbosity -gt 0 ]] && echo "Script location: $whereami"
[[ $verbosity -gt 0 ]] && test_assertions

# Test the parameters

failures=0
[[ $batch_percent -ne 0 ]] && {
	assert_condition "Batch percent $batch_percent > 0" "echo $batch_percent" ">" "0"
	assert_condition "Batch percent $batch_percent < 100" "echo $batch_percent" "<" "100"
    batch_size=0   # Calculate this later properly
} || {
	assert_condition "Batch size > 0" "echo $batch_size" ">" "0"	
	assert_condition "Batch size < 100M" "echo $batch_size" "<" "100000000"
}

[[ $interval -gt 0 ]] && assert_condition "Interval $interval is a rational value" "echo $interval" ">" "0"
[[ $cleanup -gt 0 ]] && assert_condition "Cleanup option $cleanup > 0" "echo $cleanup" ">" "0"
[[ $cleanup -gt 0 ]] && assert_condition "Cleanup option $cleanup <= 3" "echo $cleanup" "<=" "3"

# Test the connection

[[ "$ssh_tunnel" == "" ]] && PSQL=$(find_psql) || PSQL="$ssh_tunnel psql"
gtimeout=$(find_timeout)

assert_condition "Can find psql?" "echo $PSQL" "exist"
assert_condition "Can find timeout?" "echo $gtimeout" "exist"

[[ $failures -gt 0 ]] && die 2 "Critical errors found while testing environment."

#psql_wrap function depends on global PSQL options
[[ "$statement_timeout" -eq 0 ]] && gtimeout="" ||  gtimeout="$gtimeout -s 9 ${statement_timeout}s"
[[ "$hostname" == "socket" ]] && hostname="" || hostname="-h ${hostname}"
[[ "$database" == "" ]] || database="-d ${database}"
[[ "$hostuser" == "" ]] || hostuser="-U ${hostuser}"
[[ "$hostport" == "" ]] || hostport="-p ${hostport}"
connection="$hostname $database $hostuser $hostport"
[[ $verbosity -gt 1 ]] && echo "Connection: $connection"
PSQL="$gtimeout $PSQL $connection --no-psqlrc -wAv ON_ERROR_STOP=1 -v CONNECT_TIMEOUT=5 "
[[ $verbosity -gt 1 ]] && echo "PSQL: $PSQL"

assert_condition "Can connect to PostgreSQL?" "can_pg_connect" "exit0"
[[ $failures -gt 0 ]] && die 2 "Critical errors found while connecting to PostgreSQL."

pg_version=$(pg_version)
[[ $show_version == "true" ]] && { echo "PostgreSQL version is: $pg_version"; exit 0; }

assert_condition "PostgreSQL version is supported $pg_version" "echo $pg_version" ">" "90300"

[[ $failures -gt 0 ]] && die 2 "PostgreSQL version not supported: $pg_version"

# Test for movement rationality
assert_condition "Source table given $source_relation" "echo $source_relation" "exist"
assert_condition "Target table given $target_relation" "echo $target_relation" "exist"
assert_condition "Qualifications given: $qualifications" "echo $qualifications" "exist"
[[ ! $runtime == "0" ]] && assert_condition "Timeout $runtime > 0" "echo $runtime" ">" "0"
assert_condition "Schema exists $source_schema" "schema_exists $source_schema" "exit0"
assert_condition "Source table $source_relation exists?" "table_exists $source_relation $source_schema" "exit0"
[[ "$make_target" == "false" ]] && [[ "$generate" == "false" ]] && assert_condition "Target table $target_relation exists?" "table_exists $target_relation $target_schema" "exit0"
[[ "$runtime" == "0" ]] || assert_condition "Runtime of $runtime is rational" "echo $runtime" ">" "0"

[[ $failures -gt 0 ]] && die 2 "Relations not found."

[[ "$generate" == "true" ]] && [[ "$script_name" == "" ]] && script_name="pg_mv_${source_relation}_to_${target_relation}.bash"

[[ "$make_target" == "true" ]] && [[ "$generate" == "false" ]] && assert_condition "Make the target table $target_relation" "create_table_from_table $source_schema $source_relation $target_schema $target_relation" "exit0" 

[[ $failures -gt 0 ]] && die 2 "Could not create target relation."
# make a list of columns from the source, and compare them individually to the target

differences=$(diff <(get_columns $source_schema $source_relation) <(get_columns $target_schema $target_relation))
[[ "$generate" == "false" ]] && assert_condition "Source columns are identical to destination" "echo $differences" "empty"

[[ $failures -gt 0 ]] && die 2 "$differences"

# Create a transaction block SQL statement

move_count=0
[[ "$column_list" == "" ]] && column_list=$(list_columns $source_schema $source_relation)
limit_clause=
# If we are looking for a scalar batch, we don't need a real count, just that there are some tuples left.
simple_count_sql="WITH tuple_ids AS (SELECT ctid FROM $(quote_ident "$source_schema").$(quote_ident "$source_relation") WHERE $qualifications LIMIT 1 ) SELECT count(ctid) FROM tuple_ids;"
explain_count_sql="EXPLAIN SELECT ctid FROM $(quote_ident "$source_schema").$(quote_ident "$source_relation") WHERE $qualifications " 
[[ $batch_percent -gt 0 ]] && {
    # extract an estimate from the explain plan
    # Analyze the table or this count could be horrific
    echo "ANALYZE $(quote_ident $source_schema).$(quote_ident $source_relation)" | psql_wrap
    move_count=$(echo "$explain_count_sql" | psql_wrap | head -n 1 | sed -e 's/[[:alnum:]=)]*$//' -e 's/^.*=//' -e 's/[[:space:]]*$//g'; exit_code=$?; [[ $exit_code -gt 0 ]] && die $exit_code "Code was : $exit_code")
    [[ $verbosity -gt 1 ]] && echo "move count: $move_count"
    } || {
    move_count=$(echo "$simple_count_sql" | psql_wrap; exit_code=$?; [[ $exit_code -gt 0 ]] && die $exit_code "Code was: $exit_code" )
    }

assert_condition "There are more than 0 rows to move" "echo $move_count" ">" "0"
# fudge slightly for integer division
[[ $batch_percent -eq 0 ]] || { 
    batch_size=$( bc -l <<< $move_count/100.0*$batch_percent )
    batch_size=$(printf "%.0f" $batch_size) 
}
assert_condition "Batch size $batch_size is > 0" "echo $batch_size" ">" "0"

[[ $failures -gt 0 ]] && die 2 "No rows to move."

main_sql="WITH this_batch AS (SELECT ctid 
FROM $(quote_ident "$source_schema").$(quote_ident "$source_relation") 
WHERE $qualifications LIMIT $batch_size ),
batch_insert AS (INSERT INTO $(quote_ident "$target_schema").$(quote_ident "$target_relation") 
($column_list) 
SELECT $column_list 
FROM $(quote_ident "$source_schema").$(quote_ident "$source_relation")
WHERE ctid IN (SELECT ctid FROM this_batch))
DELETE FROM $(quote_ident "$source_schema").$(quote_ident "$source_relation") sr
USING this_batch b WHERE sr.ctid = b.ctid;"

[[ $verbosity -gt 0 ]] && echo "$main_sql"

# Start looping

vacuum_sql=""
case $cleanup in
    0) ;;  # nope out
    1) vacuum_sql="VACUUM (verbose) $(quote_ident "$source_schema").$(quote_ident "$source_relation");
                VACUUM (verbose) $(quote_ident "$target_schema").$(quote_ident "$target_relation");";;
    2) vacuum_sql="ANALYZE (verbose) $(quote_ident "$source_schema").$(quote_ident "$source_relation");
                ANALYZE (verbose) $(quote_ident "$target_schema").$(quote_ident "$target_relation");";;
    3) vacuum_sql="VACUUM (analyze, verbose) $(quote_ident "$source_schema").$(quote_ident "$source_relation");
                VACUUM (analyze, verbose) $(quote_ident "$target_schema").$(quote_ident "$target_relation");";;
    *) ;;
esac

[[ "$generate" == "true" ]] && {
    # Make a shell script, but don't execute it

cat <<-EOF > "$script_name"
#!$SHELL
#===============================================================================
#
#          FILE: ${script_name}
#
#         USAGE: ./${script_name}
#
#   DESCRIPTION: Move data from table $source_schema.$source_relation to $target_schema.$target_relation
#      Based on the criteria "WHERE $qualifications"
#       OPTIONS: none
#  REQUIREMENTS: ---
#        AUTHOR: $USER@$HOSTNAME
#       CREATED: $(date +'%Y-%m-%d')
#===============================================================================
set -u  # no unset variables

$([[ "${generate}" == "true" ]] && echo -e  "# Create the target table\n $PSQL -qtAc 'CREATE TABLE $(quote_ident "$target_schema").$(quote_ident "$target_relation") (LIKE $(quote_ident "$source_schema").$(quote_ident "$source_relation") INCLUDING ALL);'")

move_count=$move_count $([[ $batch_percent -gt 0 ]] && {
    echo -e "# SQL to estimate row count: \n# \$(echo '$explain_count_sql' | $PSQL -qtA | head -n 1 | sed -e 's/[[:alnum:]=)]*$//' -e 's/^.*=//' -e 's/[[:space:]]*$//g'; exit_code=\$?; [[ \$exit_code -gt 0 ]] && die \$exit_code \"Code was : \$exit_code\"\)"
} || {
    echo -e "# SQL to ensure rows exist to move: \n# echo '$simple_count_sql' | $PSQL -qtA ; exit_code=\$?; [[ \$exit_code -gt 0 ]] && die \$exit_code \"Code was: \$exit_code\""
}
)
batches=1
original_move_count=\$move_count
rows_moved=0
while [ \$move_count -gt 0 ]
do
    echo "$main_sql" | $PSQL -qtA
    exit_code=\$?
    [[ \$exit_code -gt 0 ]] && { echo 'psql encountered and error \$exit_code'; exit \$exit_code; }
    
    move_count=\$(echo '$simple_count_sql' | $PSQL -qtA ; exit_code=\$?; [[ \$exit_code -gt 0 ]] && { echo "Code was: \$exit_code"; exit \$exit_code; })
    $([[ $verbosity -gt 0 ]] && echo 'echo "Batches of '$batch_size' moved: $batches"')
    (( rows_moved=batches*$batch_size ))
    $([[ $verbosity -gt 1 ]] && echo 'echo "Rows moved: $rows_moved"')
    (( rows_left=original_move_count-rows_moved ))
    $([[ $verbosity -gt 1 ]] && [[ $batch_percent -gt 0 ]] && echo 'echo "Estimated rows left to move: $rows_left"')
    (( batches++ ))
	$([[ $verbosity -gt 1 ]] && echo '    echo "Runtime $SECONDS seconds."')
	$([[ $runtime -gt 0 ]] && echo "    [[ \$SECONDS -gt $runtime ]] && { echo 'Timeout reached, did not finish.'; exit 0; }")
    $([[ $interval -gt 0 ]] && echo  "    sleep $interval")
done

echo -e "$vacuum_sql" | $PSQL -qtA

EOF
    chmod +x "$script_name"
    exit 0    
}

batches=1
while [ $move_count -gt 0 ]
do
    # the money line
	echo "$main_sql" | psql_wrap
    exit_code=$?
    [[ $exit_code -gt 0 ]] && die $exit_code "psql encountered an error while moving data."
    # how many rows do we have left to move?
    move_count=$(echo "$simple_count_sql" | psql_wrap )
    # show some status
	[[ $verbosity -gt 0 ]] && echo "Batches of $batch_size moved: $batches"
	(( batches++ ))
	[[ $verbosity -gt 1 ]] && echo "Runtime $SECONDS seconds."
    # Exit if we were given a timeout
	[[ $runtime -gt 0 ]] && [[ $SECONDS -gt $runtime ]] && die 0 "Timeout reached"
    # Sleep if we were given an interval
    [[ $interval -gt 0 ]] && sleep $interval
done

[[ ! "$vacuum_sql" == "" ]] && [[ $verbosity -gt 0 ]] && echo -e "VACUUM SQL: $vacuum_sql"
[[ "$vacuum_sql" == "" ]] || echo -e "$vacuum_sql" | psql_wrap 

exit $?  # Go nicely.  Go.
