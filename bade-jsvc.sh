#!/bin/bash
#
# BaDe - The Bash Deployer
#
# BaDe JSVC : Manipulate JSVC (start/stop) and deploy JAR
#

#################
# Configuration #
#################

# detect this script location (also resolve links since $0 may be a softlink)
PRG="$0"
while [[ -h $PRG ]]; do
  ls=`ls -ld "$PRG"`
  link=`expr "$ls" : '.*-> \(.*\)$'`
  if expr "$link" : '/.*' > /dev/null; then
    PRG="$link"
  else
    PRG=`dirname "$PRG"`/"$link"
  fi
done
PRGDIR=`dirname "$PRG"`

# scripts used by this script 
NEXUS="$PRGDIR/bade-nexus.sh"
if [[ ! -s $NEXUS ]]; then
  echo "Nexus script ($NEXUS) could not be found !"
  exit 1
fi

#############
# Functions #
#############

# display the script usage
function usage {
  echo "BaDe (The Bash Deployer) for JSVC : manipulate JSVC Daemon (start/stop) and deploy JAR"
  echo "Available actions : init, status, start/stop/restart, deploy"
  echo "Usage :"
  echo "  $0 -a init -n APPLICATION_NAME [-q] [-t]"
  echo "     initialize the JSVC directory structure for the given application"
  echo "     ex: $0 -a init -n my-app"
  echo "  $0 -a status -n APPLICATION_NAME [-q] [-t]"
  echo "     display the status of the given application"
  echo "     ex: $0 -a status -n my-app"
  echo "  $0 -a start -n APPLICATION_NAME -c APPLICATION_DAEMON_CLASS [-i] [-q] [-t]"
  echo "     start the given application"
  echo "     ex: $0 -a start -n my-app -c com.example.app.JsvcDaemon"
  echo "  $0 -a stop -n APPLICATION_NAME -c APPLICATION_DAEMON_CLASS [-q] [-t]"
  echo "     stop the given application (if it is started)"
  echo "     ex: $0 -a stop -n my-app -c com.example.app.JsvcDaemon"
  echo "  $0 -a restart -n APPLICATION_NAME -c APPLICATION_DAEMON_CLASS [-i] [-q] [-t]"
  echo "     restart the given application"
  echo "     ex: $0 -a restart -n my-app -c com.example.app.JsvcDaemon"
  echo "  $0 -a deploy -n APPLICATION_NAME -c APPLICATION_DAEMON_CLASS -v APPLICATION_VERSION [-d] [-i] [-q] [-t]"
  echo "     deploy a specific version of an application, with a restart of the application"
  echo "     ex: $0 -a deploy -n my-app -c com.example.app.JsvcDaemon -v 1.0.0 -d"
  echo "Options : "
  echo "  -n APPLICATION_NAME : matching artifactId in nexus and directory in FS ('my-app', ...)"
  echo "  -c APPLICATION_DAEMON_CLASS : full name of the class implementing the JSVC Daemon interface ('com.example.app.JsvcDaemon')"
  echo "  -v APPLICATION_VERSION : either an exact match ('1.0.0' or '1.0.0-SNAPSHOT'), or a symbolic link :"
  echo "     RELEASE : the latest release version ('1.0.0')"
  echo "     LATEST : the latest snapshot version ('1.0.0-SNAPSHOT')"
  echo "  -d : force directory structure creation (same as calling 'init' and then 'deploy')"
  echo "  -i : interactive mode, with a tail on the log file after starting the application"
  echo "  -q : quiet mode : do not print anything, just use return status"
  echo "  -t : print time for each action"
}

# log (echo) the given message only if we are not in the "quiet" mode
function log {
  if [[ ! $QUIET && -n $1 ]]; then
    if [[ $PRINT_TIME ]]; then
      TIME=`date +%T.%2N`" "
    else
      TIME=""
    fi
    echo "$TIME$1"
  fi
}

# define a variable NEXUS_OPTS using options from this script (-q/-t/...)
function nexus_opts {
  NEXUS_OPTS=""
  [[ $QUIET ]] && NEXUS_OPTS+=" -q"
  [[ $PRINT_TIME ]] && NEXUS_OPTS+=" -t"
}

# check that the expected environment variables are set
function check_environment {
  ENV_IS_VALID=0
  if [[ -z $JSVC_APPS_BASE || ! -d $JSVC_APPS_BASE ]]; then
    [[ -z $JSVC_APPS_BASE ]] && log "JSVC_APPS_BASE is not defined !"
    [[ ! -d $JSVC_APPS_BASE ]] && log "JSVC_APPS_BASE '$JSVC_APPS_BASE' does not exists !"
    log "JSVC_APPS_BASE should be the base path for the location of all apps (where we find JSVC_APP_BASE)"
    ENV_IS_VALID=1
  fi
  return $ENV_IS_VALID
}

# check that the APP_NAME is set and JSVC_APP_BASE exists
function check_application {
  if [[ -z $APP_NAME ]]; then
    log "Missing application name !"
    return 1
  fi
  JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
  if [[ ! -d $JSVC_APP_BASE ]]; then
    log "JSVC_APP_BASE '$JSVC_APP_BASE' does not exists ! Invalid application name ?"
    return 1
  fi
  return 0
}

# create the JSVC directory structure (for initializing a new app) 
function create_jsvc_dir_structure {
  if [[ -z $APP_NAME ]]; then
    log "Missing application name !"
    return 1
  fi
  JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
  declare -a DIRS=('lib' 'logs' 'run')
  # first check if all is ok or not
  if [[ -d $JSVC_APP_BASE ]]; then
    local ALL_DIRS_OK=0
    for DIR in ${DIRS[@]}; do
      [[ ! -d $JSVC_APP_BASE/$DIR ]] && ALL_DIRS_OK=1
    done
    [[ $ALL_DIRS_OK -eq 0 ]] && return 0
  fi
  # ok we need to do some work
  log "Creating JSVC directory structure for $APP_NAME..."
  [[ ! -d $JSVC_APP_BASE ]] && mkdir $JSVC_APP_BASE
  for DIR in ${DIRS[@]}; do
    [[ ! -d $JSVC_APP_BASE/$DIR ]] && mkdir $JSVC_APP_BASE/$DIR
  done
  log "JSVC_APP_BASE is ready at $JSVC_APP_BASE"
  return 0
}

# return true if app is running, false otherwise
function is_app_running {
  if ! check_application; then
    log "Invalid application name for status !"
    return 1
  fi
  log "Checking application status for $APP_NAME..."
  JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
  JSVC_PID_FILE="$JSVC_APP_BASE/run/pid"
  if [[ -s $JSVC_PID_FILE ]]; then
    PID=`cat $JSVC_PID_FILE`
    ps "$PID" > /dev/null
    if [[ $? -eq 0 ]]; then
      log "Application is running with pid $PID"
      return 0
    else
      log "Application is not running"
      rm -f $JSVC_PID_FILE
      return 1
    fi
  else
    log "Application is not running"
    return 1    
  fi
}

# start the application if it is not running, return false in case of error
function start_app {
  if ! check_application; then
    log "Invalid application name for starting !"
    return 1
  fi
  if [[ -z $APP_DAEMON_CLASS ]]; then
    log "Missing application daemon class !"
    return 1
  fi
  log "Starting application $APP_NAME..."
  if is_app_running; then
    log "Application is already running, not starting it"
  else
    JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
    JSVC_PID_FILE="$JSVC_APP_BASE/run/pid"
    JSVC_OUT_LOG_FILE="$JSVC_APP_BASE/logs/out.log"
    JSVC_ERR_LOG_FILE="$JSVC_APP_BASE/logs/err.log"
    JSVC_CLASSPATH="$JSVC_APP_BASE/lib/*.jar"
    jsvc -outfile $JSVC_OUT_LOG_FILE -errfile $JSVC_ERR_LOG_FILE -pidfile $JSVC_PID_FILE -cp $JSVC_CLASSPATH $APP_DAEMON_CLASS
    log "Application started"
    if [[ $INTERACTIVE_MODE ]]; then
      log "Interactive mode - displaying logs from $JSVC_OUT_LOG_FILE... (Ctrl-C to quit)"
      tail -0f $JSVC_OUT_LOG_FILE &
      TAIL_PID=$!
      trap 'kill $TAIL_PID; log "Closing logs..."; return 0' INT
      wait $TAIL_PID
    fi
  fi
  return 0
}

# stop the application if it is running, return false in case of error
function stop_app {
  if ! check_application; then
    log "Invalid application name for stopping !"
    return 1
  fi
  if [[ -z $APP_DAEMON_CLASS ]]; then
    log "Missing application daemon class !"
    return 1
  fi
  log "Stopping application $APP_NAME..."
  if is_app_running; then
    JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
    JSVC_PID_FILE="$JSVC_APP_BASE/run/pid"
    JSVC_CLASSPATH="$JSVC_APP_BASE/lib/*.jar"
    jsvc -pidfile $JSVC_PID_FILE -stop -cp $JSVC_CLASSPATH $APP_DAEMON_CLASS
    log "Application stopped"
  else
    log "Application is not running, not stopping it"
  fi
  return 0
}

# restart the application
function restart_app {
  if ! check_application; then
    log "Invalid application name for restarting !"
    return 1
  fi
  if [[ -z $APP_DAEMON_CLASS ]]; then
    log "Missing application daemon class !"
    return 1
  fi
  log "Re-starting application $APP_NAME..."
  stop_app
  start_app
  return 0
}

# resolve APP_VERSION to its real version number if it is RELEASE or LATEST
function resolve_version {
  if [[ $APP_VERSION == "LATEST" || $APP_VERSION == "RELEASE" ]]; then
    log "Resolving version number for $APP_NAME - $APP_VERSION..."
    REAL_VERSION=`$NEXUS -a metadata -m version -i $APP_NAME -v $APP_VERSION -e jar -c jar-with-dependencies -q`
    if [[ $? -eq 0 && -n $REAL_VERSION ]]; then
      APP_VERSION="$REAL_VERSION"
      log "Resolved version number is $APP_VERSION"
    fi
    return $?
  fi
  return 0
}

# retrieve the artifact (either locally of download it from nexus), return false in case of error
function retrieve_artifact {
  log "Retrieving artifact..."
  JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
  INCOMING_DIR="$JSVC_APP_BASE/incoming"
  INCOMING_FILE="$INCOMING_DIR/$APP_NAME-$APP_VERSION.jar"
  [[ -d $INCOMING_DIR ]] && rm -rf $INCOMING_DIR
  mkdir -p $INCOMING_DIR
  if [[ -n $JAR_FILE && -s $JAR_FILE ]]; then
    log "Using local JAR file : $JAR_FILE"
    cp $JAR_FILE $INCOMING_FILE
  else
    nexus_opts
    if ! $NEXUS -a download -o $INCOMING_FILE -i $APP_NAME -v $APP_VERSION -e jar -c jar-with-dependencies -s $NEXUS_OPTS || [[ ! -s $INCOMING_FILE ]]; then
      rm -rf $INCOMING_DIR
      return 1
    fi
  fi
  return 0
}

# deploy an application, with a full stop/start
function deploy_app {
  if [[ $FORCE_DIRECTORY_CREATION ]]; then
    if ! create_jsvc_dir_structure; then
      log "Failed to force directory structure creation for $APP_NAME !"
      return 1
    fi
  fi
  if ! check_application; then
    log "Invalid application name for deploying !"
    return 1
  fi
  if [[ -z $APP_DAEMON_CLASS ]]; then
    log "Missing application daemon class !"
    return 1
  fi
  if [[ -z $APP_VERSION ]]; then
    log "Missing application version for deploying !"
    return 1
  fi
  log "Deploying $APP_NAME - $APP_VERSION..."
  if ! resolve_version; then
    echo "Failed to resolve version number for $APP_NAME - $APP_VERSION !"
    return 1
  fi
  if ! retrieve_artifact; then
    log "Error while retrieving JAR file. Invalid application name and/or version ?"
    return 1
  fi
  if ! stop_app; then
    log "Failed to stop application !"
    return 1
  fi
  JSVC_APP_BASE="$JSVC_APPS_BASE/$APP_NAME"
  rm -rf $JSVC_APP_BASE/lib
  mv $JSVC_APP_BASE/incoming $JSVC_APP_BASE/lib
  # TODO log rotate for out.log / err.log
  if ! start_app; then
    log "Failed to start application !"
    return 1
  fi
  return 0
}

##########
# Script #
##########

# extract options
while getopts ":a:n:v:c:f:hdiqt" opt; do
  case $opt in
    a)
      ACTION=$OPTARG
      ;;
    n)
      APP_NAME=$OPTARG
      ;;
    v)
      APP_VERSION=$OPTARG
      ;;
    c)
      APP_DAEMON_CLASS=$OPTARG
      ;;
    f)
      JAR_FILE=$OPTARG
      ;;
    d)
      FORCE_DIRECTORY_CREATION=true
      ;;
    i)
      INTERACTIVE_MODE=true
      ;;
    q)
      QUIET=true
      ;;
    t)
      PRINT_TIME=true
      ;;
    h)
      usage
      exit 0
      ;;
    \?)
      echo "Invalid option -$OPTARG"
      usage
      exit 1
      ;;
    *)
      echo "Option -$OPTARG requires an argument."
      usage
      exit 1
      ;;
    :)
      echo "Option -$OPTARG requires an argument."
      usage
      exit 1
      ;;
  esac
done

# make sure the environment is set up
if ! check_environment; then
  echo "Environment is not properly set up. Exiting !"
  exit 1
fi

# do the job !
case "$ACTION" in
  init)
    create_jsvc_dir_structure
    ;;
  status) 
    is_app_running
    ;;
  start) 
    start_app
    ;;
  stop)
    stop_app
    ;;
  restart)
    restart_app
    ;;
  deploy)
    deploy_app
    ;;
  *)
    echo "Invalid action $ACTION"
    usage
    ;;
esac

exit $?

