#!/bin/bash

cat 1>&2 <<-EOF
  This script is not to run on any system.
  Anh K. Huynh adds this banner to prevent script from being used.

  The original script is here
    https://github.com/mozilla-services/squid-rpm/blob/47880414f17affdbb634b6f0a19a342995fb60f6/SOURCES/squid.init
EOF

exit 0

# chkconfig: - 90 25
# pidfile: /var/run/squid.pid
# config: /etc/squid/squid.conf
#
### BEGIN INIT INFO
# Provides: squid
# Short-Description: starting and stopping Squid Internet Object Cache
# Description: Squid - Internet Object Cache. Internet object caching is \
#       a way to store requested Internet objects (i.e., data available \
#       via the HTTP, FTP, and gopher protocols) on a system closer to the \
#       requesting site than to the source. Web browsers can then use the \
#       local Squid cache as a proxy HTTP server, reducing access time as \
#       well as bandwidth consumption.
### END INIT INFO


PATH=/usr/bin:/sbin:/bin:/usr/sbin
export PATH

# Source function library.
. /etc/rc.d/init.d/functions

# Source networking configuration.
. /etc/sysconfig/network

if [ -f /etc/sysconfig/squid ]; then
	. /etc/sysconfig/squid
fi

# don't raise an error if the config file is incomplete
# set defaults instead:
SQUID_OPTS=${SQUID_OPTS:-""}
SQUID_PIDFILE_TIMEOUT=${SQUID_PIDFILE_TIMEOUT:-20}
SQUID_SHUTDOWN_TIMEOUT=${SQUID_SHUTDOWN_TIMEOUT:-100}
SQUID_CONF=${SQUID_CONF:-"/etc/squid/squid.conf"}
SQUID_PIDFILE_DIR="/var/run/squid"
SQUID_USER="squid"
SQUID_DIR="squid"

# determine the name of the squid binary
[ -f /usr/sbin/squid ] && SQUID=squid

prog="$SQUID"

# determine which one is the cache_swap directory
CACHE_SWAP=`sed -e 's/#.*//g' $SQUID_CONF | \
	grep cache_dir | awk '{ print $3 }'`

RETVAL=0

probe() {
	# Check that networking is up.
	[ ${NETWORKING} = "no" ] && exit 1

	[ `id -u` -ne 0 ] && exit 4

	# check if the squid conf file is present
	[ -f $SQUID_CONF ] || exit 6
}

start() {
	# Check if $SQUID_PIDFILE_DIR exists and if not, lets create it and give squid permissions.
	if [ ! -d $SQUID_PIDFILE_DIR ] ; then mkdir $SQUID_PIDFILE_DIR ; chown -R $SQUID_USER.$SQUID_DIR $SQUID_PIDFILE_DIR; fi
	probe

	parse=`$SQUID -k parse -f $SQUID_CONF 2>&1`
	RETVAL=$?
	if [ $RETVAL -ne 0 ]; then
		echo -n $"Starting $prog: "
		echo_failure
		echo
		echo "$parse"
		return 1
	fi
	for adir in $CACHE_SWAP; do
		if [ ! -d $adir/00 ]; then
			echo -n "init_cache_dir $adir... "
			$SQUID -z -F -f $SQUID_CONF >> /var/log/squid/squid.out 2>&1
		fi
	done
	echo -n $"Starting $prog: "
	$SQUID $SQUID_OPTS -f $SQUID_CONF >> /var/log/squid/squid.out 2>&1
	RETVAL=$?
	if [ $RETVAL -eq 0 ]; then
		timeout=0;
		while : ; do
			[ ! -f /var/run/squid.pid ] || break
			if [ $timeout -ge $SQUID_PIDFILE_TIMEOUT ]; then
				RETVAL=1
				break
			fi
			sleep 1 && echo -n "."
			timeout=$((timeout+1))
		done
	fi
	[ $RETVAL -eq 0 ] && touch /var/lock/subsys/$SQUID
	[ $RETVAL -eq 0 ] && echo_success
	[ $RETVAL -ne 0 ] && echo_failure
	echo
	return $RETVAL
}

stop() {
	echo -n $"Stopping $prog: "
	$SQUID -k check -f $SQUID_CONF >> /var/log/squid/squid.out 2>&1
	RETVAL=$?
	if [ $RETVAL -eq 0 ] ; then
		$SQUID -k shutdown -f $SQUID_CONF &
		rm -f /var/lock/subsys/$SQUID
		timeout=0
		while : ; do
			[ -f /var/run/squid.pid ] || break
			if [ $timeout -ge $SQUID_SHUTDOWN_TIMEOUT ]; then
				echo
				return 1
			fi
			sleep 2 && echo -n "."
			timeout=$((timeout+2))
		done
		echo_success
		echo
	else
		echo_failure
		if [ ! -e /var/lock/subsys/$SQUID ]; then
			RETVAL=0
		fi
		echo
	fi
	rm -rf $SQUID_PIDFILE_DIR/*
	return $RETVAL
}

reload() {
	$SQUID $SQUID_OPTS -k reconfigure -f $SQUID_CONF
}

restart() {
	stop
	rm -rf $SQUID_PIDFILE_DIR/*
	start
}

condrestart() {
	[ -e /var/lock/subsys/squid ] && restart || :
}

rhstatus() {
	status $SQUID && $SQUID -k check -f $SQUID_CONF
}


case "$1" in
start)
	start
	;;

stop)
	stop
	;;

reload|force-reload)
	reload
	;;

restart)
	restart
	;;

condrestart|try-restart)
	condrestart
	;;

status)
	rhstatus
	;;

probe)
	probe
	;;

*)
	echo $"Usage: $0 {start|stop|status|reload|force-reload|restart|try-restart|probe}"
	exit 2
esac

exit $?
