if [ ! -z ${CLOVER_SERVER_HEAP_SIZE} ]; then
	export CATALINA_OPTS="$CATALINA_OPTS -Xms${CLOVER_SERVER_HEAP_SIZE}m -Xmx${CLOVER_SERVER_HEAP_SIZE}m"
fi

if [ ! -z ${RESERVED_CODE_CACHE_SIZE} ]; then
	export CATALINA_OPTS="$CATALINA_OPTS -XX:ReservedCodeCacheSize=${RESERVED_CODE_CACHE_SIZE}m"
fi
	
if [ ! -z ${MAX_CACHED_BUFFER_SIZE} ]; then	
	export CATALINA_OPTS="$CATALINA_OPTS -Djdk.nio.maxCachedBufferSize=${MAX_CACHED_BUFFER_SIZE}"
fi	

# GC settings
export CATALINA_OPTS="$CATALINA_OPTS -XX:+UseG1GC"
export CATALINA_OPTS="$CATALINA_OPTS -XX:ParallelGCThreads=4"
export CATALINA_OPTS="$CATALINA_OPTS -XX:ConcGCThreads=4"
export CATALINA_OPTS="$CATALINA_OPTS -XX:InitiatingHeapOccupancyPercent=30"
export CATALINA_OPTS="$CATALINA_OPTS -XX:G1ReservePercent=10"
export CATALINA_OPTS="$CATALINA_OPTS -XX:MaxGCPauseMillis=100"
 
# JMX for Core Server - port 8686
export CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.config.file=$CATALINA_HOME/cloverconf/jmx-conf.properties"
export CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.port=8686"
export CATALINA_OPTS="$CATALINA_OPTS -Dcom.sun.management.jmxremote.rmi.port=8687"
export CATALINA_OPTS="$CATALINA_OPTS -Djava.rmi.server.hostname=${RMI_HOSTNAME}"

export CATALINA_OPTS="$CATALINA_OPTS -Dclover.config.file=$CLOVER_CONF_FILE"
export CATALINA_OPTS="$CATALINA_OPTS -Dclover.clover.home=$CLOVER_HOME_DIR"
export CATALINA_OPTS="$CATALINA_OPTS -Dclover.default.config.file=$CATALINA_HOME/cloverconf/default_clover.properties"
export CATALINA_OPTS="$CATALINA_OPTS -Dshared.clover.lib=$CLOVER_LIB_DIR"
export CATALINA_OPTS="$CATALINA_OPTS -Dlog4j2.appender.stdout.level=info"

CLOVER_LICENSE_FILE=$CLOVER_CONF_DIR/license.dat
if [ -f $CLOVER_LICENSE_FILE ]; then
	export CATALINA_OPTS="$CATALINA_OPTS -Dclover.license.file=$CLOVER_LICENSE_FILE"
fi

# SERVER_JAVA_OPTS should be at the end of CATALINA_OPTS, so that it has the highest priority
# Used for custom command line arguments for CloverDX Core Server
export CATALINA_OPTS="$CATALINA_OPTS ${SERVER_JAVA_OPTS}"

# Avoiding JVM delays caused by random number generation
export CATALINA_OPTS="$CATALINA_OPTS -Djava.security.egd=file:/dev/./urandom"