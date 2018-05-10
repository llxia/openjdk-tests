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

echo "***** Running Benchmark Script *****"

export PRODUCT=pxa6480sr6
export BM_DIR_NAME=SPECjbb2015GMR

#Just for testing purposes: to be removed later
currentDir="$(pwd)"
echo "$currentDir"
echo "Current Dir: $PWD"
ls -lart

#This is where all the benchmark packages are downloaded. All downloaded SDKs exist under ./sdks
RUN_DIR=$1
export RUN_DIR=$RUN_DIR

#TODO: Remove these once the use of STAF has been eliminated from all the benchmark scripts
export PATH=/usr/local/staf/bin:$PATH
export LD_LIBRARY_PATH=/usr/local/staf/lib:$LD_LIBRARY_PATH

benchmark_dir="$RUN_DIR/${BM_DIR_NAME}"
echo "benchmark_dir: $benchmark_dir"

cd $benchmark_dir
echo "Current Dir: $(pwd)"

#Temporarily setting the SDK to this since Perfxposh doesn't have Espresso access so we have use the one that's already
#there on the machine.
LAST_BUILD=`cat "$WORKSPACE/JDK_LAST_BUILD.txt"`
JDK_DIR=$JAVA_BIN/..

export JDK_DIR=${JDK_DIR}
#export JDK="${PRODUCT}-$LAST_BUILD"#

######### Generated Script #########
export JDK_OPTIONS="-Xaggressive -Dreflect.cache=boot -Dcom.ibm.enableClassCaching=true -Dcom.ibm.cacheLatestUserDefinedClassLoader=true -Dcom.ibm.crypto.provider.doAESInHardware=true -XtlhPrefetch -Xdump:java+system:events=user"
export CTRL_OPTIONS=""
export NO_GROUPS="2"
export NO_INJECTORS="1"
export HW_THREADS="56"
#export TI_OPTIONS="-Xms2g -Xmx2g -Xmn1500m -Xgcpolicy:gencon -Xlp -Xcompressedrefs"
#export BE_OPTIONS="-Xms24g -Xmx24g -Xmn20g -Xgcpolicy:gencon -Xlp -Xcompressedrefs"

#current testing machine does not support large page. Change the cmd to -Xlp:objectheap:pagesize=64K
export TI_OPTIONS="-Xms2g -Xmx2g -Xmn1500m -Xgcpolicy:gencon -Xlp:objectheap:pagesize=64K -Xcompressedrefs"
export BE_OPTIONS="-Xms24g -Xmx24g -Xmn20g -Xgcpolicy:gencon -Xlp:objectheap:pagesize=64K -Xcompressedrefs"

export GRP1TXIAFF="numactl --cpunodebind=0 --membind=0"
export GRP1BEAFF="numactl --cpunodebind=0 --membind=0"
export GRP2TXIAFF="numactl --cpunodebind=1 --membind=1"
export GRP2BEAFF="numactl --cpunodebind=1 --membind=1"

echo "********** START OF NEW TESTCI BENCHMARK JOB **********"
echo "Benchmark Name: SPECjbb2015 Benchmark Variant: multi_2grp_gencon"
echo "Benchmark Product: $JDK"

bash ./run_multi.sh 
