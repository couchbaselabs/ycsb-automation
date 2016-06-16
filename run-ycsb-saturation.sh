set -x
# Expect the following directories under ${YTOP}
# YCSB - git clone of a YCSB repo
# testrunner - CB testrunner repo
# cb-ycsb-automation - specific scripts developed to automate the saturation, scale out, collecting results, 

runid=4VM-111
cbhost=
cluster_hosts=
cbhosts_rest=
maxclients=1
maxthreads=8
stepincrease=4
recordcount=100000
opscount=10000000
exec_time=120
stale="OK"
wait_time=60
loaddata=N
version=4.5.0
buildnum=0
buildurl="NONE"
build_install="N"
ycsb_install="N"
ycsb_binding="SDK2" # or "REST"
ycsb_run="N"
ycsb_cbsdk1_repo="https://github.com/brianfrankcooper/YCSB.git"
#ycsb_cbsdk2_repo="https://github.com/daschl/YCSB.git"
ycsb_cbsdk2_repo="https://github.com/couchbaselabs/YCSB"
ycsb_cbrest_repo="https://github.com/subalakr/YCSB.git"
ycsb_cbsdk1db="couchbase"
ycsb_cbsdk2db="couchbase2"
ycsb_cbrestdb="couchbaserest"
ycsb_db=${ycsb_cbsdk2db}
memindex="N"
iot="N"
index_name="wle_idx"
iot_index_stmt="create index ${index_name} on default(meta().id, field1, field0, field7, field6, field9, field8, field3, field2, field5, field4)"
metaid_index_stmt="create index ${index_name} on default(meta().id)"
create_index_stmt=${metaid_index_stmt}
workload="workloade"
csv_conversion="Y"
data_mem_quota=30000
index_mem_quota=30000

export YTOP=`pwd`

# Parse input
while getopts "D:C:S:h:lBW:miyR:t:s:r:e:b:u:c:v:V:" opt; do
    case "$opt" in
	D) # runiD
	    runid=$OPTARG
	    ;;
	C) # Cluster Host, arguments should be a list of IPs separated by space, put round bracket to make it an array
	    cluster_hosts=($OPTARG)
	    cbhosts_rest=${OPTARG}
	    if [ ${#cluster_hosts[*]} == 0 ]
	    then
		echo "-C <host map> e.g. -C \"172.23.100.190 172.23.100.191 172.23.100.192 172.23.100.194\" should at least has one IP address"
		exit
	    else
		# REST API requires the entire list of host IPs separated by commas to be passed into the ycsb invocation
		cbhosts_rest=${cbhosts_rest// /\,}
		echo cbhosts_rest is: ${cbhosts_rest}
	    fi
	    # assign the first node to be the master
	    cbhost=${cluster_hosts[0]}
	    echo cbhost is ${cbhost}, cluster hosts is ${cluster_hosts[*]}

	    # TODO: Generate the server.ini & construct the cbhosts_rest list dynamically
	    ;;
	S) # mdS
	    services=($OPTARG)
	    if [ ${#services[*]} == 0 ]
	    then
		echo "-S <MDS map> e.g. -C \"kv,index,n1ql kv,n1ql kv,n1ql kv,n1ql\" separated by space and should at least has one combo"
		exit
	    fi
	    ;;
	h) # a host to connect to for load, and other index creation operation or to run the workload
	    cbhost=$OPTARG
	    ;;
	l) loaddata="Y"
	   ;;
	B) build_install="Y"
	   ;;
	W) workload=$OPTARG
	   ;;
	m) memindex="Y"
	   ;;
	i) # full doc index
	    iot="Y"
	    create_index_stmt=${iot_index_stmt}
	    ;;
	y) ycsb_install="Y"
	   ;;
	R)
	    ycsb_run="Y"
	    ycsb_binding=$OPTARG
	    if [ ${ycsb_binding} == "SDK2" ]
	    then
		ycsb_db=${ycsb_cbsdk2db}
	    elif [ ${ycsb_binding} == "SDK1" ]
	    then
		ycsb_db=${ycsb_cbsdk1db}
	    else
		if [ ${ycsb_binding} == "REST" ]
		then
		   ycsb_db=${ycsb_cbrestdb}
		else
		    echo "-R <binding> where Binding should be SDK1 or SDK 2 or REST"
		    exit
		fi
	    fi
	    ;;
	t)  maxthreads=$OPTARG
            ;;
	s)  stepincrease=$OPTARG
            ;;
	r)  recordcount=$OPTARG
            ;;
	e)  exec_time=$OPTARG
            ;;
	b)  buildnum=$OPTARG
            ;;
	u) buildurl=$OPTARG
	   ;;
	c) maxclients=$OPTARG
	   ;;
	v) csv_conversion=$OPTARG
	   ;;
        V) version=$OPTARG
	   ;;
    esac
done

echo "Inputs: maxthreads= ${maxthreads}, stepincrease=${stepincrease}, recordcount=${recordcount}, exec_time=${exec_time}, buildnum=${buildnum}, loaddata=${loaddata}, maxclients=${maxclients}, build_install=${build_install}, ycsb_run=${ycsb_run}"

##########################  Install a build  ####################################################

if [ ${build_install} == "Y" ]
then
    echo "install a build ......."
    echo "YTOP is: $YTOP"
    # first check that the testrunner is already available, if not the pull it
    if [ ! -d ${YTOP}/testrunner ]
    then
	cd ${YTOP}
	git clone https://github.com/couchbase/testrunner
    fi

    # generate the server.ini file to be used for installation
    
    
    cd ${YTOP}/testrunner
    if [ $buildurl != "NONE" ]
    then
	python scripts/install.py -i ${YTOP}/server.ini -p product=cb,version=${version}-${buildnum},parallel=true,init_nodes=False,url=${buildurl}
    else
	python scripts/install.py -i ${YTOP}/server.ini -p product=cb,version=${version}-${buildnum},parallel=true,init_nodes=False
    fi
    
    # Setup the first  node, use this node for index and query
    curl -X POST http://${cbhost}:8091/pools/default -d memoryQuota=${data_mem_quota} -d indexMemoryQuota=${index_mem_quota}
    # services could be any combination of n1ql,kv,index
    curl http://${cbhost}:8091/node/controller/setupServices -d "services=${services[0]}"
    curl -X POST http://${cbhost}:8091/settings/web -d port=8091 -d username=Administrator -d password=password

    sleep 10

    # add other nodes and rebalancing
    echo "##################### Adding and rebalancing nodes ####################################"

    # all other nodes are joinging the first node. host count exclude the first host
    hcount=$((${#cluster_hosts[@]}-1))
    ns_host_list="ns_1@${cbhost}"
    indexer_nodes_ref=()
    for idx in `seq 0 ${hcount}`
    do
	if [[ ${services[idx]}  == *"index"* ]]
	then
	    indexer_nodes_ref+=(${idx})
	    # The indexer node 
	    # We don't need this. indexer=${cluster_hosts[idx]}
	fi

	# adding the next node to the cluster
	if [ ${idx} -gt 0 ]
	then 
	    curl -u Administrator:password ${cbhost}:8091/controller/addNode -d "hostname=${cluster_hosts[idx]}&user=Administrator&password=password&services=${services[idx]}"
	    # also build of host list to be rebalance, concat the string
	    ns_host_list="${ns_host_list},ns_1@${cluster_hosts[idx]}"
	fi
    done

    # Now Rebalance the cluster
    # The format for the Relance command argument is
    # ejectedNodes=&knownNodes=ns_1@172.23.97.145,ns_1@172.23.97.172,ns_1@172.23.97.83,ns_1@172.23.99.221 
   curl -v -u Administrator:password -X POST http://${cbhost}:8091/controller/rebalance -d "ejectedNodes=&knownNodes=${ns_host_list}" 

    # Waiting for rebalance to finish
    sleep 60
    echo "create default bucket"
    curl -XPOST http://${cbhost}:8091/pools/default/buckets -u Administrator:password -d name=default \
	 -d ramQuotaMB=${data_mem_quota} -d authType=none -d proxyPort=11224 -d threadsNumber=8 \
	 -d evictionPolicy=fullEviction

    sleep 10
    # Change index settings for WAL_SIZE, Timeout etc.
    if [ ${#indexer_nodes_ref[*]} -gt 0 ]
    then 
	curl -u Administrator:password ${cluster_hosts[${indexer_nodes_ref[0]}]}:9102/settings | python -m json.tool > ./index-settings.json
	sed -i '/indexer.settings.wal_size/c\    "indexer.settings.wal_size": 40960,' index-settings.json
	sed -i '/indexer.settings.scan_timeout/c\    "indexer.settings.scan_timeout": 120000,' index-settings.json
	if [ ${memindex} == "N" ]
	then
	    sed -i '/indexer.settings.storage_mode/c\    "indexer.settings.storage_mode": "forestdb",' index-settings.json
	else
	    sed -i '/indexer.settings.storage_mode/c\    "indexer.settings.storage_mode": "memory_optimized",' index-settings.json
	fi
	
	curl -u Administrator:password ${cluster_hosts[${indexer_nodes_ref[0]}]}:9102/settings -d @./index-settings.json

	sleep 10
    fi

    # create indexes here instead of the during the loading phase
    for j in ${indexer_nodes_ref[@]}
    do
	# Create Index before load so that we don't wait for index creation to finish. The quoting of the statement is rather nasty
	curl -XPOST -u Administrator:password http://${cbhost}:8093/query/service -d "statement=${create_index_stmt/${index_name}/${index_name}_${j}}"
    done
fi

############################################# Install YCSB #################################

if [ ${ycsb_install} == "Y" ]
then

    echo "Install YCSB ..."
    
    for c in `seq 1 ${maxclients}`
    do
	cd $YTOP
	if [ -d ./YCSB_SDK2_${c} ]
	then
	    rm -rf ./YCSB_SDK1_${c}
	    rm -rf ./YCSB_SDK2_${c}
	    rm -rf ./YCSB_REST_${c}
	fi

	# Clone Brian Cooper's repo
	git clone ${ycsb_cbsdk1_repo}
	mv YCSB YCSB_SDK1_${c}
	cd ${YTOP}/YCSB_SDK1_${c}
	git fetch origin
	git checkout origin
	mvn -pl com.yahoo.ycsb:${ycsb_cbsdk1db}-binding -am clean package -Dmaven.test.skip -Dcheckstyle.skip=true
	

	# Clone the YCSB Michael's repo
	cd ${YTOP}
	git clone ${ycsb_cbsdk2_repo}
	mv YCSB YCSB_SDK2_${c}
	cd ${YTOP}/YCSB_SDK2_${c}
	git fetch origin
	git checkout origin/couchbase2
	mvn -pl com.yahoo.ycsb:${ycsb_cbsdk2db}-binding -am clean package -Dmaven.test.skip -Dcheckstyle.skip=true

	# Clone the YCSB Subhashni's repo
	cd ${YTOP}
	git clone ${ycsb_cbrest_repo}
	mv YCSB YCSB_REST_${c}
	cd ${YTOP}/YCSB_REST_${c}xf
	git fetch origin
	git checkout origin/refresh
	mvn -pl com.yahoo.ycsb:${ycsb_cbrestdb}-binding -am clean package -Dmaven.test.skip -Dcheckstyle.skip=true
	
    done
    echo "Install YCSB done!"    

fi

############################################## Load Data  #################################

if  [ ${loaddata} == "Y" ]
then
    echo "Load YCSB data ...."
    
    # Go to the first YCSB client directory and run the load from there
    if [ ! -d ${YTOP}/YCSB_SDK2_1 ]
    then
	echo "YCSB software has not been installed, please run <command> -y Y to install YCSB"
	exit
    fi
    
    cd ${YTOP}/YCSB_SDK2_1

    # Create Index before load so that we don't wait for index creation to finish
    # curl -XPOST http://${cbhost}:8093/query/service \
    # 	 -d 'statement='"${create_index_stmt}"'&creds=[{"user":"admin:Administrator", "pass":"password"}]"'

    # Now Load data, spit it to a different extension so that we don't get mixed up with 
    ./bin/ycsb load couchbase2 \
	       -jvm-args=-Dcom.couchbase.connectTimeout\=300000 \
	       -jvm-args=-Dcom.couchbase.kvTimeout\=60000 \
	       -P workloads/${workload} -p couchbase.host=${cbhost} -threads 6 \
	       -p recordcount=${recordcount}  2> ${YTOP}/${runid}.loadlog 1>  ${YTOP}/${runid}.loadres

    # sleep for a bit to wait for the index to complete
    sleep 120
    echo "Load YCSB data done!"
else
     echo "Loading data not included"
fi

###########################  Iterate through the thread count ###################################

if  [ ${ycsb_run} == "Y" ]
then

    # Clean any existing log files and result files for this client directory
    rm -v "${runid}".load*
    for c in `seq 1 ${maxclients}`
    do
    	rm -fv ${YTOP}/YCSB_*"${c}"/"${runid}"*.log ${YTOP}/YCSB_*"${c}"/"${runid}"*.res ${YTOP}/YCSB_*"${c}"/"${runid}"*.csv
    done

    # For each step function of threadcount starting from 4, lauch all clients 
    for i in `seq 4 ${stepincrease} ${maxthreads}`
    do
    	for c in `seq 1 ${maxclients}`
    	do
    	    # spawn $c clients each running with ${i} threads
    	    cd ${YTOP}/YCSB_${ycsb_binding}_${c}
	    if [ ${ycsb_binding} == "SDK2" ] 
	    then
		dbname=${ycsb_db}
		connProp="couchbase.host"
		connStr=${cbhost}
	    elif [ ${ycsb_binding} == "SDK1" ]
	    then
		# Note that for SDK1, the connection string is the only different in the way we invoke
		dbname=${ycsb_db}
		connProp="couchbase.url"
		connStr="http://${cbhost}:8091/pools"
	    else
		dbname=${ycsb_cbrestdb}
		connProp="couchbase.n1qlhosts"
		connStr="${cbhosts_rest}"
	    fi

	    file_name=${runid}-${workload}-${c}-${i}
	    res_file="${file_name}".res
	    log_file="${file_name}".log
	    csv_file="${file_name}".csv
	    nohup ./bin/ycsb run ${dbname} \
		  -jvm-args=-Dcom.couchbase.connectTimeout\=15000 \
		  -jvm-args=-Dcom.couchbase.kvTimeout\=60000 \
		  -s -P workloads/${workload} -p ${connProp}="${connStr}" \
		  -threads ${i} -p recordcount=${recordcount} \
		  -p operationcount=${opscount} \
		  -p maxexecutiontime=${exec_time} \
		  -p couchbase.upsert=true \
		  -p couchbase.queryEndpoints=1  \
		  -p couchbase.epoll=true \
		  -p couchbase.boost=0 \
		  2> ${log_file} 1> ${res_file} &

    	done
	
    	# need to know when this iteration  finished for all the ycsb client  we have spawn, wait for exec_time or check the process id
    	let "w = ${exec_time} + ${wait_time}"
    	echo "sleep ${w} seconds"
    	sleep ${w}

	# Now generate the CSV file for the result of this iteration of thread count ${i}
	if [ ${csv_conversion} == "Y" ]
	then
	    cd ${YTOP}
	    for c in `seq 1 ${maxclients}`
	    do
		for f in `ls ${YTOP}/YCSB_${ycsb_binding}_${c}/${runid}*-${i}.res`
		do
		    # csv file name is the same as the result file except the extension is .csv
		    # arg1: result file, arg2: csv file
		    echo python ycsb-csv.py ${f} ${f/\.res/\.csv} ${runid} ${ycsb_binding} ${workload} ${i} ${recordcount}
		    python ycsb-csv.py ${f} ${f/\.res/\.csv} ${runid} ${ycsb_binding} ${workload} ${i} ${recordcount} 
		done
	    done
	fi
    done

    # Convert the restuls file into csv
    cd ${YTOP}

    # Now zip up all the results
    tar cvzf ${runid}-${ycsb_binding}-${workload}-${maxclients}-moi-${memindex}-fulldoc-${iot}.gz \
	"${runid}".load* YCSB_${ycsb_binding}_[1-${maxclients}]/"${runid}"*.* 

fi
