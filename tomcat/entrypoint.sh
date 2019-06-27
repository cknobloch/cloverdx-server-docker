#!/bin/bash

#min memory limits in bytes
MIN_MEMORY_SIZE=2147483648
MIN_SERVER_HEAP_SIZE=512
MIN_WORKER_HEAP_SIZE=1024

available_memory() {
	local mem_file="/sys/fs/cgroup/memory/memory.limit_in_bytes"
	local mem_file_soft="/sys/fs/cgroup/memory/memory.soft_limit_in_bytes"
	if [[ -r "${mem_file}" && -r "${mem_file_soft}" ]]; then
		local max_mem_cgroup="$(cat ${mem_file})"
		local max_mem_cgroup_soft="$(cat ${mem_file_soft})"
		if [ ${max_mem_cgroup:-0} -lt ${max_mem_cgroup_soft:-0} ]; then
			export SYSTEM_TOTAL_MEMORY=${max_mem_cgroup}
			echo ${max_mem_cgroup}
		else
			echo ""
		fi
	else
		echo ""
	fi
}

bytes_to_megabytes() {
	local val=$(($1 / 1048576))
	echo "${val}"
}

#gets value from the given parameter and converts it to megabytes
#value can be a number (then it is considered as value in MB)
# or number with units (e.g. "1024m")
#supported units: 
#	megabytes (m)
#	gigabytes (g)
parse_to_get_megabytes() {
	local value=$1
	if [[ ${value} =~ ([0-9]+)[gG]{1} ]]; then
		value=$((${BASH_REMATCH[1]} * 1024))
	elif [[ ${value} =~ ([0-9]+)[mM]{1} ]]; then	
		value=${BASH_REMATCH[1]}
	fi
	echo ${value}
}

print_mem_info() {
	local info="Total available memory:\t ${SYSTEM_TOTAL_MEMORY_MB}MB\n
	OS memory:\t\t ${OS_MEM}MB\n
	Server memory:\t\t ${CLOVER_SERVER_HEAP_SIZE}MB\n
	Worker memory:\t\t ${CLOVER_WORKER_HEAP_SIZE}MB\n
	ReservedCodeCacheSize:\t ${RESERVED_CODE_CACHE_SIZE}MB\n
	maxCachedBufferSize:\t ${MAX_CACHED_BUFFER_SIZE}"
	echo ${info}
}

compute_memory() {
	local available_mem=$(available_memory)
	
	if [ ! -z ${available_mem} ]; then
		export SYSTEM_TOTAL_MEMORY=${available_mem}
		SYSTEM_TOTAL_MEMORY_MB=$(bytes_to_megabytes "${available_mem}")
		if [ ${available_mem} -lt ${MIN_MEMORY_SIZE} ]; then
			>&2 echo "Insufficient memory set, expected at least $(bytes_to_megabytes "${MIN_MEMORY_SIZE}")MB, got ${SYSTEM_TOTAL_MEMORY_MB}MB."
			exit 1
		fi	
	else
		SYSTEM_TOTAL_MEMORY_MB=$(bytes_to_megabytes "${MIN_MEMORY_SIZE}")
	fi

	export CLOVER_SERVER_HEAP_SIZE=$(parse_to_get_megabytes "$CLOVER_SERVER_HEAP_SIZE")
	export CLOVER_WORKER_HEAP_SIZE=$(parse_to_get_megabytes "$CLOVER_WORKER_HEAP_SIZE")

	if [[ ${SERVER_JAVA_OPTS} =~ -Xmx([0-9]+[mMgG]?) ]]; then
		export CLOVER_SERVER_HEAP_SIZE=$(parse_to_get_megabytes "${BASH_REMATCH[1]}")
	fi
	
	if [ -z ${CLOVER_SERVER_HEAP_SIZE} ] && [ ! -z ${CLOVER_WORKER_HEAP_SIZE} ]; then
		>&2 echo "Parameter CLOVER_SERVER_HEAP_SIZE is not set."
		exit 1
	fi

	if [ ! -z ${CLOVER_SERVER_HEAP_SIZE} ] && [ -z ${CLOVER_WORKER_HEAP_SIZE} ]; then
		>&2 echo "Parameter CLOVER_WORKER_HEAP_SIZE is not set."
		exit 1
	fi

	QUARTER_OF_MEMORY=$((${SYSTEM_TOTAL_MEMORY_MB}/4))

	if [ -z ${CLOVER_SERVER_HEAP_SIZE} ]; then
		export CLOVER_SERVER_HEAP_SIZE=$(($QUARTER_OF_MEMORY > 8192 ? 8192 : $QUARTER_OF_MEMORY))
	fi

	if [ ${SYSTEM_TOTAL_MEMORY_MB} -lt 8192 ]; then
		export RESERVED_CODE_CACHE_SIZE=128
		export MAX_CACHED_BUFFER_SIZE=65536
	elif [ ${SYSTEM_TOTAL_MEMORY_MB} -lt 16384 ]; then
		export RESERVED_CODE_CACHE_SIZE=256
		export MAX_CACHED_BUFFER_SIZE=65536
	elif [ ${SYSTEM_TOTAL_MEMORY_MB} -lt 32768 ]; then
		export RESERVED_CODE_CACHE_SIZE=256
		export MAX_CACHED_BUFFER_SIZE=131072
	elif [ ${SYSTEM_TOTAL_MEMORY_MB} -lt 65536 ]; then
		export RESERVED_CODE_CACHE_SIZE=256
		export MAX_CACHED_BUFFER_SIZE=262144
	else
		export RESERVED_CODE_CACHE_SIZE=512
		export MAX_CACHED_BUFFER_SIZE=262144
	fi

	export OS_MEM=$(($QUARTER_OF_MEMORY-$RESERVED_CODE_CACHE_SIZE > 8192 ? 8192 : $QUARTER_OF_MEMORY-$RESERVED_CODE_CACHE_SIZE))

	if [ -z $CLOVER_WORKER_HEAP_SIZE ]; then
		export CLOVER_WORKER_HEAP_SIZE=$((${SYSTEM_TOTAL_MEMORY_MB} - (${OS_MEM} + ${CLOVER_SERVER_HEAP_SIZE} + ${RESERVED_CODE_CACHE_SIZE})))
	fi

	if [ ${CLOVER_SERVER_HEAP_SIZE} -lt ${MIN_SERVER_HEAP_SIZE} ]; then
		>&2 echo "Server's heap memory is too low. It must be at least ${MIN_SERVER_HEAP_SIZE}MB."
		>&2 echo -e $(print_mem_info)
		exit 1
	fi

	if [ ${CLOVER_WORKER_HEAP_SIZE} -lt ${MIN_WORKER_HEAP_SIZE} ]; then
		>&2 echo "Worker's heap memory is too low. It must be at least ${MIN_WORKER_HEAP_SIZE}MB."
		>&2 echo -e $(print_mem_info)
		exit 1
	fi
}

compute_memory
#print info about memory settings
#echo -e $(print_mem_info)

USER=cloverdx
USER_ID=${LOCAL_USER_ID:-1000}

echo "Creating $USER user"
adduser \
	--disabled-password \
	--gecos "" \
	--home "/home/$USER" \
	--shell "/bin/bash" \
	--uid "$USER_ID" \
	"$USER"

echo "Changing ownership of $CATALINA_HOME"
chown -R $USER:$USER $CATALINA_HOME
chown -R $USER:$USER $CLOVER_HOME_DIR
chown -R $USER:$USER $CLOVER_DATA_DIR

#create empty folder for config files
if [ ! -d $CLOVER_CONF_DIR ]; then
	gosu $USER mkdir -p $CLOVER_CONF_DIR
fi	

if [ ! -d $CLOVER_HOME_DIR ]; then
	echo "Creating empty folder for config files $CLOVER_HOME_DIR"
	gosu $USER mkdir -p $CLOVER_HOME_DIR
fi	

if [ ! -f $CLOVER_CONF_FILE ]; then
	echo "Creating default $CLOVER_CONF_FILE"
	gosu $USER cp "$CATALINA_CONF_DIR/clover_example.properties" $CLOVER_CONF_FILE
fi

if [ ! -f $JNDI_CONF_FILE ]; then
	echo "Creating default $JNDI_CONF_FILE"
	gosu $USER cp "$CATALINA_CONF_DIR/jndi-conf_example.xml" $JNDI_CONF_FILE
fi

if [ ! -f $JMX_CONF_FILE ]; then
	echo "Creating default $JMX_CONF_FILE"
	gosu $USER cp "$CATALINA_CONF_DIR/jmx-conf_example.properties" $JMX_CONF_FILE
fi

gosu $USER cp $JMX_CONF_FILE $CATALINA_HOME/cloverconf
chmod 0400 $CATALINA_HOME/cloverconf/jmx-conf.properties # If SSL is used, jmx-conf.properties must be only readable by the owner (r--,---,---)

if [ ! -f $HTTPS_CONF_FILE ]; then
	echo "Creating default $HTTPS_CONF_FILE"
	gosu $USER cp "$CATALINA_CONF_DIR/https-conf_example.xml" $HTTPS_CONF_FILE
fi

if [ ! -d $CLOVER_HOME_DIR/tomcat-lib ]; then
	echo "Creating ${CLOVER_HOME_DIR}/tomcat-lib"
	gosu $USER mkdir $CLOVER_HOME_DIR/tomcat-lib
	echo "Copying JDBC drivers to ${CLOVER_HOME_DIR}/tomcat-lib"
	gosu $USER cp /var/dbdrivers/* ${CLOVER_HOME_DIR}/tomcat-lib/
fi

gosu $USER mkdir -p $CLOVER_HOME_DIR/worker-lib

#set SERVER_JAVA_OPTS to empty string if not set
if [ -z "$SERVER_JAVA_OPTS" ]; then
	export SERVER_JAVA_OPTS=""
fi

#set WORKER_JAVA_OPTS to empty string if not set
if [ -z "$WORKER_JAVA_OPTS" ]; then
	export WORKER_JAVA_OPTS=""
fi

#execute Tomcat
#save Tomcat standard output to catalina.out
echo "Starting Tomcat"
exec gosu $USER ./bin/catalina.sh run
