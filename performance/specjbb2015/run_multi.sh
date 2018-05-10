#!/bin/bash
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

###############################################################################
# Sample script for running SPECjbb2015 in MultiJVM mode.
# 
# This sample script demonstrates running the Controller, TxInjector(s) and 
# Backend(s) in separate JVMs on the same server.
###############################################################################


############# Start of Clean Up (Moving files from previous runs) #############
# Copied run_cleanup_multi.sh here in order to have just one script instead of two
# This would slighty simplify the process of launching jobs on PerfNext

folderName="leftoverResults/"`date +%d%m%y-%H%M%S`
mkdir -p $folderName

# Copy S*ECjbb2015.out instead of moving it since it's used by STAF for STDOUT. 
# If we move this file (and not copy), benchmark would give a STAF error and fail 
# since STAF expects the file to be in the run directory 
cp SPECjbb2015.out ${folderName}

# Emptying the existing SPECjbb2015.out file
echo " " > SPECjbb2015.out

echo "Tidying previous result files into results/ dir"
mkdir -p results
mv specjbb2015-M-* results

echo "Removing stdout from previous run"
echo "moving" `ls con*roller.out con*roller.log con*roller.gclog GRP*.*.log GRP*.*.log GRP*.*.gclog GRP*.*.gclog 2>/dev/null` "to ${folderName}"
mv con*roller.out con*roller.log con*roller.gclog GRP*.*.log GRP*.*.log GRP1.*.gclog GRP*.*.gclog ${folderName} 

echo "Done cleanup"
############################### End of Clean Up  ###############################

function usage() {
    echo "Please make sure these environment variables are all set:
      <JDK_DIR> <JDK_OPTIONS> <TI_OPTIONS> <BE_OPTIONS> <HW_THREADS>
Mandatory variables:
     JDK_DIR: base dir containing JDKs, eg: /java/perffarm/sdks
 JDK_OPTIONS: Common options to apply to all TxI and BE processes, eg: -Xaggressive
  TI_OPTIONS: Specific options for the TxI, eg: -Xms2g -Xmx2g -Xmn1500m -Xgcpolicy:gencon
  BE_OPTIONS: Specific options for the BE, eg: -Xms9g -Xmx9g -Xgcpolicy:balanced
  HW_THREADS: Number of hardware threads available on the system
Optional variables:
CTRL_OPTIONS: Any additional options for the controller
   NO_GROUPS: Number of groups for multi-group mode (default: 2)
NO_INJECTORS: Number of TxI's per group (default: 1)
  GRP1TXIAFF: Affinity command for Group 1 TxI(s)   (GRP2, GRP3, etc for additional groups)
   GRP1BEAFF: Affinity command for Group 1 Backend
  "
}

function mandatory() {
    if [ -z "${!1}" ]; then
        echo "${1} not set"
        usage
	exit
    fi
}

function optional() {
    if [ -z "${!1}" ]; then
        echo -n "${1} not set (ok)"
	if [ -n "${2}" ]; then
	    echo -n ", default is: ${2}"
	fi
	echo ""
    fi
}
function on_exit()
{
    echo "Caught kill, killing processes $PID_LIST $CPU_PID"
    kill $PID_LIST $CPU_PID
    echo "Done, exiting"
    exit 1
}

function setlp()
{
	if [ -f "/home/jbench/bin/setlp" ]; then
		echo "Enabling Large Pages"
        . /home/jbench/bin/setlp
	fi
}

function checklp()
{
    countgclogs=`ls -1 *.gclog 2>/dev/null | wc -l`
    if [ $countgclogs != 0 ]; then
		echo "Status: Running $0 - gclogs found"
        grep "ageSize" *.gclog
    else
        echo "Status: Running $0 - No gclogs found"
    fi
}

setlp

trap on_exit SIGINT SIGQUIT SIGTERM

mandatory JDK_DIR
# Options to be applied to all 'group' JDKs (TxI and BE for each group).  Eg:
# -Xaggressive -Dreflect.cache=boot -Dcom.ibm.enableClassCaching=true -Dcom.ibm.cacheLatestUserDefinedClassLoader=true
mandatory JDK_OPTIONS
# Any additional options required for TxI, eg: -Xms2048m -Xmx2048m -Xmn1536m -Xgcpolicy:gencon
mandatory TI_OPTIONS
#Specific JDK options for backends, eg: -Xmx9000m -Xms9000m -Xgcpolicy:balanced
mandatory BE_OPTIONS
# Number of hardware threads on the system (used to determine thread counts for group JVMs)
mandatory HW_THREADS
# Any additional options required for controller (probably empty)
optional CTRL_OPTIONS

# Number of Groups (TxInjectors mapped to Backend) to expect
GROUP_COUNT=${NO_GROUPS:-2}
# Number of TxInjector JVMs to expect in each Group
TI_JVM_COUNT=${NO_INJECTORS:-1}

optional NO_GROUPS $GROUP_COUNT
optional NO_INJECTORS $TI_JVM_COUNT

# Check that affinity has been set for each group
for ((GNUM=1; $GNUM<$GROUP_COUNT+1; GNUM=$GNUM+1)); do
    optional "GRP${GNUM}TXIAFF"
    optional "GRP${GNUM}BEAFF"
done

# Check for and kill any existing JVMs (may be stuck due to a previous failed run / bad JDK)
bash kill_java.sh

# Date stamp for result files generated by this run
CUR_DATE=`date +"%Y%m%d-%H%M%S"`

PLATFORM=`/bin/uname | cut -f1 -d_`
echo "Platform identified as: ${PLATFORM}"

# GC will use a 1:1 GC thread to HW thread ratio
GC_THREADS=$(($HW_THREADS/$GROUP_COUNT))
# Calculate Fork/join pool number if not manually specified.
if DUMMY=$(echo $CTRL_OPTIONS | grep 'specjbb.forkjoin.workers'); then
	JBB_FJWORKERS=''
else
	# Fork/join pool will use a 2:1 FJ thread to HW thread ratio.
	NO_THREADS=$(($GC_THREADS*2))
	JBB_FJWORKERS=-Dspecjbb.forkjoin.workers=$NO_THREADS
fi

# Benchmark options for Controller / TxInjector JVM / Backend
# Please use -Dproperty=value to override the default and property file value
# Please add -Dspecjbb.controller.host=$CTRL_IP (this host IP) to the benchmark options for the all components
# and -Dspecjbb.time.server=true to the benchmark options for Controller 
# when launching MultiJVM mode in virtual environment with Time Server located on the native host.
JBB_OPTS="-Dspecjbb.group.count=$GROUP_COUNT -Dspecjbb.txi.pergroup.count=$TI_JVM_COUNT"
#JBB_PROFILING=-Dspecjbb.profiling.mode=INTRUSIVE
ALLGRPOPTS="$JBB_FJWORKERS $JDK_OPTIONS"
ALLGCOPTS="$JBB_PROFILING -Xconcurrentlevel0 -Xgcthreads$GC_THREADS"
GCLOGPARM="-Xverbosegclog"

# Java options for Controller / TxInjector / Backend JVM
JAVA_OPTS_C="-Xms512m -Xmx512m -Xgcpolicy:gencon -Xcompressedrefs $JBB_FJWORKERS $CTRL_OPTIONS $ALLGCOPTS ${GCLOGPARM}:controller.gclog"
JAVA_OPTS_TI="$TI_OPTIONS $ALLGCOPTS $ALLGRPOPTS"
JAVA_OPTS_BE="$BE_OPTIONS $ALLGCOPTS $ALLGRPOPTS"

# Check for (and rename) an old log file, so that our archive step at the end picks up the right one
OLD_DATA_FILE=`ls specjbb2015-M-*-00001.data.gz 2>/dev/null`
if [ -n "$OLD_DATA_FILE" -a -e "$OLD_DATA_FILE" ]; then
    echo "Data found from a previous run: $OLD_DATA_FILE"
    OLD_DATA_RENAME="${OLD_DATA_FILE}_old_$CUR_DATE"
    mv $OLD_DATA_FILE $OLD_DATA_RENAME
    echo "Renamed to: $OLD_DATA_RENAME"
fi

echo
echo "Results files will be tagged with date: $CUR_DATE"
echo
echo "JAVA DIR: $JDK_DIR"
echo
echo "Controller java opt: $JAVA_OPTS_C"
echo
echo "TxInject java opt: $JAVA_OPTS_TI"
echo
echo "Back end java opt: $JAVA_OPTS_BE"
echo

###############################################################################
# This benchmark requires a JDK7 compliant Java VM.  If such a JVM is not on
# your path already you must set the JAVA environment variable to point to
# where the 'java' executable can be found.
###############################################################################

if [ -x "${JDK_DIR}/jre/bin/java" ]
then
	JAVA=${JDK_DIR}/jre/bin/java
else
	JAVA=${JDK_DIR}/bin/java
fi

echo "JAVA FULLPATH: $JAVA"
echo

#which $JAVA > /dev/null 2>&1
#if [ $? -ne 0 ]; then
if [ -z "$JAVA" ]; then
    echo "ERROR: Could not find a 'java' executable. Please set the JAVA environment variable or update the PATH."
    exit 1
fi

echo "GROUP count is $GROUP_COUNT"
echo "TxI count is $TI_JVM_COUNT per group"
echo
echo "TEST Transaction Injector java -version:"
echo "$JAVA $JAVA_OPTS_TI -version"
$JAVA $JAVA_OPTS_TI -version
echo
echo "TEST Backend java -version:"
echo "$JAVA $JAVA_OPTS_BE -version"
$JAVA $JAVA_OPTS_BE -version
echo

echo "Launching SPECjbb2015 in MultiJVM mode..."
echo

echo "Start Controller JVM"
$JAVA $JAVA_OPTS_C $JBB_OPTS -jar specjbb2015.jar -m MULTICONTROLLER 2>controller.log > controller.out &

CTRL_PID=$!
echo "Controller PID = $CTRL_PID"
# start a list of PIDs to be monitored (or killed, if the script is killed)
PID_LIST="$CTRL_PID"
# start a list of output files to collect (and clean up) at the end of the run
# - exclude controller.out, because STAF will echo this file after this script completes.
OUT_LIST="controller.log controller.gclog"

sleep 5

# **** Execute groups ****
for ((GNUM=1; $GNUM<$GROUP_COUNT+1; GNUM=$GNUM+1)); do
    GROUPID=GRP$GNUM
    echo -e "\nStarting JVMs from $GROUPID:"
    for ((JNUM=1; $JNUM<$TI_JVM_COUNT+1; JNUM=$JNUM+1)); do
        JVMID=txiJVM$JNUM
        TI_NAME=$GROUPID.TxInjector.$JVMID
		AFFVAR="GRP${GNUM}TXIAFF"
        echo "    Start $TI_NAME with affinity ${!AFFVAR}"
		if [ $PLATFORM = "CYGWIN" ]; then
	    	cmd /C start /B ${!AFFVAR} $JAVA $JAVA_OPTS_TI ${GCLOGPARM}:$TI_NAME.gclog -jar specjbb2015.jar -m TXINJECTOR -G $GROUPID -J $JVMID > $TI_NAME.log 2>&1 &
		else
	    	${!AFFVAR} $JAVA $JAVA_OPTS_TI ${GCLOGPARM}:$TI_NAME.gclog -jar specjbb2015.jar -m TXINJECTOR -G $GROUPID -J $JVMID > $TI_NAME.log 2>&1 &
		fi
        echo -e "\t$TI_NAME PID = $!"
        PID_LIST="$PID_LIST $!"
		OUT_LIST="$OUT_LIST $TI_NAME.gclog $TI_NAME.log"
        sleep 5
    done
    
    JVMID=beJVM
    BE_NAME=$GROUPID.Backend.$JVMID
    AFFVAR="GRP${GNUM}BEAFF"
    echo "    Start $BE_NAME with affinity ${!AFFVAR}"
    
    if [ $PLATFORM = "CYGWIN" ]; then
		cmd /C start /B ${!AFFVAR} $JAVA $JAVA_OPTS_BE ${GCLOGPARM}:$BE_NAME.gclog -jar specjbb2015.jar -m BACKEND -G $GROUPID -J $JVMID > $BE_NAME.log 2>&1 &
    else
		${!AFFVAR} $JAVA $JAVA_OPTS_BE ${GCLOGPARM}:$BE_NAME.gclog -jar specjbb2015.jar -m BACKEND -G $GROUPID -J $JVMID > $BE_NAME.log 2>&1 &
    fi
    
    echo -e "\t$BE_NAME PID = $!"
    PID_LIST="$PID_LIST $!"
    OUT_LIST="$OUT_LIST $BE_NAME.gclog $BE_NAME.log"
    sleep 5
done

if [[ ${PLATFORM} != *"390"* ]]
then
	echo
	echo "Starting CPU monitoring ... PIDs = $PID_LIST"
	./monitor_cpu.sh $PID_LIST &
	CPU_PID=$!
	OUT_LIST="$OUT_LIST top_output.txt"
fi

echo
echo "SPECjbb2015 is running..."
echo "Please monitor controller.out for progress"

echo "Launching monitor_progress.sh"
bash monitor_progress.sh $$ controller.out &

wait $CTRL_PID
echo
echo "Controller has stopped"

if [[ ${PLATFORM} != *"390"* ]]
then
	echo
	echo "Stopping CPU monitoring ..."
	sleep 5
	kill $CPU_PID
	wait $CPU_PID
	./summarize_cpu.sh $PID_LIST
	OUT_LIST="$OUT_LIST cpu_results.csv rss_results.csv"

	echo "+++ CPU data"
	cat ./cpu_results.csv
	echo "--- CPU data"

	echo "+++ RSS data"
	cat ./rss_results.csv
	echo "--- RSS data"
fi

# In future, verbose GC parsing can go here
# Input: controller.out, GRP1.Backend.beJVM.gclog, GRP2.Backend.beJVM.gclog
echo
echo "Running checklp"
checklp
echo

# Output the results 
cat controller.out

ARCHIVE="specjbb2015-M-${CUR_DATE}.data.gz"
ARCHIVE_PERF="specjbb2015-M-${CUR_DATE}.perflogs.zip"
echo "Archiving logs:"
# Note: assumes that previous runs have been cleaned up properly
mv specjbb2015-M-*-00001.data.gz $ARCHIVE
echo "SPECjbb2015 data renamed to $ARCHIVE"
# Archive the logs that were generated. SPECjbb2015.out is generated only when running via STAF.
zip $ARCHIVE_PERF $OUT_LIST controller.out SPECjbb2015.out
echo "Perf logs zipped to $ARCHIVE_PERF"

echo "Cleaning up"
rm $OUT_LIST

echo
echo "SPECjbb2015 has finished"
echo

exit 0
