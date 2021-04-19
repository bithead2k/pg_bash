#!/bin/echo -e "Include in calling script with\n source environment_tests.bash"
#===============================================================================
#
#          FILE: assertion_engine.bash
#
#         USAGE: ./assertion_engine.bash
#
#   DESCRIPTION: 
#
#       OPTIONS: ---
#  REQUIREMENTS: ---
#          BUGS: ---
#         NOTES: ---
#        AUTHOR: Kirk L. Roybal (DBRE), kirk.roybal@doordash.com
#  ORGANIZATION: OmniTI/Credativ/Instaclustr/Doordash
#       CREATED: 04/06/2021 00:14:15
#      REVISION:  ---
#===============================================================================

export failures=0
[[ -f $(dirname $(readlink -f "$0"))/lib/status.bash ]] && source $(dirname $(readlink -f "$0"))/lib/status.bash

function assert_condition () {
#---  FUNCTION  ----------------------------------------------------------------
#          NAME:  assert_condition
#   DESCRIPTION:  assert that a condition is true
#       Expects global accumulator variable "failures" 
#    PARAMETERS:  name of test, condition to assert, conditional operator, expected result
#       RETURNS:  pass/fail 0/1
#-------------------------------------------------------------------------------

    test_message=$1
    test_cmd=$2
    test_operator=$3
    test_condition=${4:-}

	echo -n "$test_message   "          # output to the console for SysV style logging
	result=1                            #presume failure
	case $test_operator in
		"="|"eq")  fail_msg="$test_cmd $test_operator $test_condition"; [[ $($2) -eq $4 ]] && result=0 || result=1 ;;
		"<>"|"ne") fail_msg="$test_cmd $test_operator $test_condition"; [[ $($2) -ne $4 ]] && result=0 || result=1 ;;
		">"|"gt")  fail_msg="$test_cmd $test_operator $test_condition"; [[ $($2) -gt $4 ]] && result=0 || result=1 ;;
		"<"|"lt")  fail_msg="$test_cmd $test_operator $test_condition"; [[ $($2) -lt $4 ]] && result=0 || result=1 ;;
		">="|"ge") fail_msg="$test_cmd $test_operator $test_condition"; [[ $($2) -ge $4 ]] && result=0 || result=1 ;;
		"<="|"le") fail_msg="$test_cmd $test_operator $test_condition"; [[ $($2) -le $4 ]] && result=0 || result=1 ;;
		"same")    fail_msg="$test_cmd == $test_condition"; [[ "$($2)" = "$4" ]] && result=0 || result=1 ;;
		"unlike")  fail_msg="$test_cmd != $test_condition"; [[ "$($2)" != "$4" ]] && result=0 || result=1 ;;
		"empty")   fail_msg="$test_cmd == ''"; [[ -z "$($2)" ]] && result=0 || result=1 ;;
		"exist")   fail_msg="$test_cmd <> ''"; [[ ! -z "$($2)" ]] && result=0 || result=1 ;;
		"exit0")   eval $2; result=$?
			       fail_msg="$test_cmd returns $result expected 0"
			       [[ $result -eq 0 ]] && result=0 || result=1 ;;
		"exit!0")  eval $2; result=$?
			       fail_msg="$test_cmd returns $result expected !0"
			       [[ $result -ne 0 ]] && result=0 || result=1 ;; 
		*)         echo -n "  operator not supported"; result=1 ;; 
	esac    # --- end of case ---
	[[ $result -eq 0 ]] && success "$1" || {
		failure "$1"
		echo ""
		echo -n "$fail_msg"
		(( failures++ )) #global accumulator
		}
	echo ""  #add a carriage return
    #preserve the ability to check after each test
    return $result
}  # <-- end assert_condition



function test_assertions() {

failures=0
#-------------------------------------------------------------------------------
# Unit test the testing harness so we're not fighting fire with fire
#-------------------------------------------------------------------------------
echo "Unit tests for the testing framework."
echo "-------------------------------------"
assert_condition "unit =" "echo 1" "=" "1"
assert_condition "unit <>" "echo 1" "<>" "2"
assert_condition "unit >" "echo 2" ">" "1"
assert_condition "unit <" "echo 1" "<" "2"
assert_condition "unit >=" "echo 1" ">=" "1"
assert_condition "unit >=" "echo 2" ">=" "1"
assert_condition "unit <=" "echo 1" "<=" "1"
assert_condition "unit <=" "echo 1" "<=" "2"
assert_condition "unit same" "echo $0" "same" "$0"
assert_condition "unit unlike" "echo $0" "unlike" "yada"
assert_condition "unit empty" "echo " "empty"
assert_condition "unit exist" "echo 1" "exist"
assert_condition "unit exit0" "echo 1 > /dev/null" "exit0"
assert_condition "unit exit!0" "test -f /no_file_here > /dev/null" "exit!0"
echo ""
echo "These unit tests will fail by design."
echo "-------------------------------------"
assert_condition "unit fail =" "echo 1" "=" "2"
assert_condition "unit fail <>" "echo 1" "<>" "1"
assert_condition "unit fail >" "echo 1" ">" "2"
assert_condition "unit fail <" "echo 1" "<" "0"
assert_condition "unit fail >=" "echo 1" ">=" "2"
assert_condition "unit fail <=" "echo 1" "<=" "0"
assert_condition "unit fail same" "echo 1" "same" "2"
assert_condition "unit fail unlike" "echo 1" "unlike" "1"
assert_condition "unit fail empty" "echo 1" "empty"
assert_condition "unit fail exist" "" "exist"
assert_condition "unit fail exit0" "test -f /file_not_here > /dev/null" "exit0"
assert_condition "unit fail exit!0" "echo 1 > /dev/null" "exit!0"
echo ""
echo "Begin testing for upgrade conditions."
echo "--------------------------------------"

#-------------------------------------------------------------------------------
# No tests should fail from this point forward
#-------------------------------------------------------------------------------
failures=0  # reset the accumulator
}
