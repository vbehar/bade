#!/bin/bash
#
# BaDe - The Bash Deployer
#
# BaDe Tomcat : Manipulate Tomcat (start/stop) and deploy WAR
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
  echo "BaDe (The Bash Deployer) for Tomcat : manipulate Tomcat (start/stop) and deploy WAR"
  echo "Available actions : init, status, start/stop/restart, deploy, update-conf [-all]"
  echo "Usage (for 1 application) :"
  echo "  $0 -a init -n APPLICATION_NAME [-q] [-t]"
  echo "     initialize the tomcat directory structure for the given application"
  echo "     ex: $0 -a init -n my-app"
  echo "  $0 -a status -n APPLICATION_NAME [-q] [-t]"
  echo "     display the status of the tomcat instance for the given application"
  echo "     ex: $0 -a status -n my-app"
  echo "  $0 -a start -n APPLICATION_NAME [-m] [-i] [-q] [-t]"
  echo "     start the tomcat instance for the given application"
  echo "     ex: $0 -a start -n my-app"
  echo "  $0 -a stop -n APPLICATION_NAME [-q] [-t]"
  echo "     stop the tomcat instance for the given application (if it is started)"
  echo "     ex: $0 -a stop -n my-app"
  echo "  $0 -a restart -n APPLICATION_NAME [-m] [-i] [-q] [-t]"
  echo "     restart the tomcat instance for the given application"
  echo "     ex: $0 -a restart -n my-app"
  echo "  $0 -a deploy -n APPLICATION_NAME -v APPLICATION_VERSION [-e ENVIRONMENT] [-c] [-d] [-m] [-i] [-q] [-t]"
  echo "     deploy a specific version of an application, with a restart of the tomcat instance"
  echo "     ex: $0 -a deploy -n my-app -v 1.0.0 -e prod -c -d -m"
  echo "  $0 -a update-conf -n APPLICATION_NAME -e ENVIRONMENT [-m] [-i] [-q] [-t]"
  echo "     update the tomcat configuration (using the latest RELEASE version) and restart tomcat"
  echo "     ex: $0 -a update-conf -n my-app -e prod"
  echo "  $0 -a monitoring -n APPLICATION_NAME [-q] [-t]"
  echo "     check that the application is well deployed by calling some pre-configured urls"
  echo "     ex: $0 -a monitoring -n my-app"
  echo "Usage (for multiple applications) :"
  echo "  $0 -a init-all -l LIST_OF_APPLICATIONS [-w WAIT_DURATION] [-q] [-t]"
  echo "     initialize the tomcat directory structures for all given applications"
  echo "     ex: $0 -a init-all -l my-app,my-app-2,my-app-3 -w 10"
  echo "  $0 -a status-all -l LIST_OF_APPLICATIONS [-w WAIT_DURATION] [-q] [-t]"
  echo "     display the status of the tomcat instances for all given applications"
  echo "     ex: $0 -a status-all -l my-app,my-app-2,my-app-3 -w 10"
  echo "  $0 -a start-all -l LIST_OF_APPLICATIONS [-w WAIT_DURATION] [-m] [-i] [-q] [-t]"
  echo "     start the tomcat instances for all given applications"
  echo "     ex: $0 -a start-all -l my-app,my-app-2,my-app-3"
  echo "  $0 -a stop-all -l LIST_OF_APPLICATIONS [-w WAIT_DURATION] [-q] [-t]"
  echo "     stop the tomcat instances for all given applications (if they are started)"
  echo "     ex: $0 -a stop-all -l my-app,my-app-2,my-app-3"
  echo "  $0 -a restart-all -l LIST_OF_APPLICATIONS [-w WAIT_DURATION] [-m] [-i] [-q] [-t]"
  echo "     re-start the tomcat instances for all given applications"
  echo "     ex: $0 -a restart-all -l my-app,my-app-2,my-app-3"
  echo "  $0 -a deploy-all -l LIST_OF_APPLICATIONS -v APPLICATION_VERSION [-e ENVIRONMENT] [-w WAIT_DURATION] [-c] [-d] [-m] [-i] [-q] [-t]"
  echo "     deploy all given applications, either with RELEASE or LATEST version"
  echo "     ex: $0 -a deploy-all -l my-app,my-app-2,my-app-3 -v LATEST -e prod -c -d -m"
  echo "  $0 -a update-conf-all -l LIST_OF_APPLICATIONS -e ENVIRONMENT [-w WAIT_DURATION] [-m] [-i] [-q] [-t]"
  echo "     update the tomcat configuration (using the latest RELEASE version) and restart tomcat for all given applications"
  echo "     ex: $0 -a update-conf-all -l my-app,my-app-2,my-app-3 -e prod"
  echo "Options : "
  echo "  -n APPLICATION_NAME : matching artifactId in nexus and directory in FS ('my-app', 'my-app-2', ...)"
  echo "  -l LIST_OF_APPLICATIONS : comma-separated list of applications ('my-app,my-app-2')"
  echo "  -v APPLICATION_VERSION : either an exact match ('1.0.0' or '1.0.1-SNAPSHOT'), or a symbolic link :"
  echo "     RELEASE : the latest release version ('1.0.0')"
  echo "     LATEST : the latest snapshot version ('1.0.1-SNAPSHOT')"
  echo "  -e ENVIRONMENT : name of the environment when deploying ('test', 'uat', 'prod', ...)"
  echo "  -w WAIT_DURATION : duration to wait (in seconds) between each application when executing an *-all action"
  echo "  -c : force configuration update (same as calling 'update-conf' and then 'deploy')"
  echo "  -d : force directory structure creation (same as calling 'init' and then 'deploy')"
  echo "  -m : check monitoring (after a tomcat start), and fail if the monitoring fails"
  echo "  -i : interactive mode, with a tail on the log file after starting tomcat"
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

# wait $WAIT_DURATION
function wait {
  if [[ -n $WAIT_DURATION && $WAIT_DURATION -gt 0 ]]; then
    log "Waiting $WAIT_DURATION seconds..."
    sleep $WAIT_DURATION
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
  if [[ -z $CATALINA_HOME || ! -d $CATALINA_HOME ]]; then
    [[ -z $CATALINA_HOME ]] && log "CATALINA_HOME is not defined !"
    [[ ! -d $CATALINA_HOME ]] && log "CATALINA_HOME '$CATALINA_HOME' does not exists !"
    log "CATALINA_HOME should be the full path of the Tomcat install"
    ENV_IS_VALID=1
  fi
  if [[ -z $WEBAPPS_BASE || ! -d $WEBAPPS_BASE ]]; then
    [[ -z $WEBAPPS_BASE ]] && log "WEBAPPS_BASE is not defined !"
    [[ ! -d $WEBAPPS_BASE ]] && log "WEBAPPS_BASE '$WEBAPPS_BASE' does not exists !"
    log "WEBAPPS_BASE should be the base path for the location of all webapps (where we find CATALINA_BASE)"
    ENV_IS_VALID=1
  fi
  return $ENV_IS_VALID
}

# check that the APP_NAME is set and CATALINA_BASE exists
function check_application {
  if [[ -z $APP_NAME ]]; then
    log "Missing application name !"
    return 1
  fi
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  if [[ ! -d $CATALINA_BASE ]]; then
    log "CATALINA_BASE '$CATALINA_BASE' does not exists ! Invalid application name ?"
    return 1
  fi
  return 0
}

# return true if the application is allowed on the current host
function is_app_allowed_on_host {
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  HOSTS_DENY_FILE="$CATALINA_BASE/conf/hosts.deny"
  if [[ -s $HOSTS_DENY_FILE ]]; then
    HOST=`hostname`
    for HOST_DENY in `cat $HOSTS_DENY_FILE`; do
      if [[ -n $HOST_DENY && $HOST == $HOST_DENY ]]; then
        return 1
      fi
    done
  fi
  return 0
}

# return true if the monitoring of the application succeeded (app is deployed and working)
function check_monitoring {
  if ! check_application; then
    log "Invalid application name for monitoring !"
    return 1
  fi
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  MONITORING_CONF_FILE="$CATALINA_BASE/conf/monitoring.properties"
  if [[ ! -f $MONITORING_CONF_FILE ]]; then
    log "Missing MONITORING_CONF_FILE '$MONITORING_CONF_FILE' !"
    return 1
  fi
  log "Checking monitoring for $APP_NAME..."
  source $MONITORING_CONF_FILE 
  if [[ -z $APPLICATION_HTTP_PORT ]]; then
    log "Missing APPLICATION_HTTP_PORT !"
    return 1
  fi
  [[ -n $MONITORING_USER_PASSWD ]] && local CURL_USER_PASSWD="--user $MONITORING_USER_PASSWD"
  FAILED_PATHS=""
  for MONITORING_PATH in `echo $MONITORING_PATHS | tr "," " "`; do
    MONITORING_URL="http://localhost:$APPLICATION_HTTP_PORT$MONITORING_PATH"
    log "checking $MONITORING_URL..."
    HTTP_CODE=`curl --silent --fail --connect-timeout 300 --max-time 300 --retry 2 --retry-delay 10 --retry-max-time 300 --no-keepalive --write-out %{http_code} --output /dev/null --url "$MONITORING_URL" $CURL_USER_PASSWD`
    CURL_RES=$?
    if [[ $CURL_RES -gt 0 || $HTTP_CODE -ge 400 ]]; then
      FAILED_PATHS+="$MONITORING_PATH(res=$CURL_RES,code=$HTTP_CODE),"
    fi
  done
  if [[ -n $FAILED_PATHS ]]; then
    log "Monitoring failed for : $FAILED_PATHS"
    return 1
  fi
  log "Monitoring succeeded"
  return 0
}

# create the tomcat directory structure (for initializing a new app) 
function create_tomcat_dir_structure {
  if [[ -z $APP_NAME ]]; then
    log "Missing application name !"
    return 1
  fi
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  declare -a DIRS=('conf' 'logs' 'temp' 'webapps' 'work')
  # first check if all is ok or not
  if [[ -d $CATALINA_BASE ]]; then
    local ALL_DIRS_OK=0
    for DIR in ${DIRS[@]}; do
      [[ ! -d $CATALINA_BASE/$DIR ]] && ALL_DIRS_OK=1
    done
    [[ $ALL_DIRS_OK -eq 0 ]] && return 0
  fi
  # ok we need to do some work
  log "Creating tomcat directory structure for $APP_NAME..."
  [[ ! -d $CATALINA_BASE ]] && mkdir $CATALINA_BASE
  for DIR in ${DIRS[@]}; do
    [[ ! -d $CATALINA_BASE/$DIR ]] && mkdir $CATALINA_BASE/$DIR
  done
  log "CATALINA_BASE is ready at $CATALINA_BASE"
  return 0
}

# create multiple tomcat directories structures at once
function create_all_tomcats_dir_structure {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for creating all tomcat directory structure !"
    return 1
  fi
  log "Creating tomcat directory structure for $APP_LIST..."
  APPS_OK=""
  APPS_NOK=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    if create_tomcat_dir_structure; then
      APPS_OK+="$APP_NAME,"
    else
      APPS_NOK+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_OK ]] && log "Finished ! Creation succeeded for : $APPS_OK"
  if [[ -n $APPS_NOK ]]; then
    log "Creation failed for : $APPS_NOK"
    return 1
  fi
  return 0
}

# return true if tomcat is running, false otherwise
function is_tomcat_running {
  if ! check_application; then
    log "Invalid application name for status !"
    return 1
  fi
  log "Checking tomcat status for $APP_NAME..."
  if ! is_app_allowed_on_host; then
    log "$APP_NAME is not allowed on this host ($HOST). Doing nothing."
    return 0
  fi
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  CATALINA_PID="$CATALINA_BASE/catalina.pid"
  if [[ -s $CATALINA_PID ]]; then
    PID=`cat $CATALINA_PID`
    ps "$PID" > /dev/null
    if [[ $? -eq 0 ]]; then
      log "Tomcat is running with pid $PID"
      return 0
    else
      log "Tomcat is not running"
      rm -f $CATALINA_PID
      return 1
    fi
  else
    log "Tomcat is not running"
    return 1    
  fi
}

# start multiple tomcat instances at once, return false in case of error
function are_all_tomcats_running {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for status !"
    return 1
  fi
  log "Checking tomcat status for $APP_LIST..."
  APPS_RUNNING=""
  APPS_NOT_RUNNING=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    if is_tomcat_running; then
      APPS_RUNNING+="$APP_NAME,"
    else
      APPS_NOT_RUNNING+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_RUNNING ]] && log "Finished ! Tomcat is running for : $APPS_RUNNING"
  if [[ -n $APPS_NOT_RUNNING ]]; then
    log "Tomcat is not running for : $APPS_NOT_RUNNING"
    return 1
  fi
  return 0
}

# start the tomcat if it is not running, return false in case of error
function start_tomcat {
  if ! check_application; then
    log "Invalid application name for starting tomcat !"
    return 1
  fi
  log "Starting tomcat for $APP_NAME..."
  if ! is_app_allowed_on_host; then
    log "$APP_NAME is not allowed on this host ($HOST). Doing nothing."
    return 0
  fi
  if is_tomcat_running; then
    log "Tomcat is already running, not starting it"
  else
    export CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
    export CATALINA_PID="$CATALINA_BASE/catalina.pid"
    JAVA_OPTS_FILE="$CATALINA_BASE/conf/jvm.options"
    if [[ -s $JAVA_OPTS_FILE ]]; then
      export JAVA_OPTS=`cat $JAVA_OPTS_FILE`
    fi
    $CATALINA_HOME/bin/catalina.sh start
    log "Tomcat started"
    if [[ $INTERACTIVE_MODE ]]; then
      LOGS_FILE="$CATALINA_BASE/logs/catalina.out"
      log "Interactive mode - displaying logs from $LOGS_FILE... (Ctrl-C to quit)"
      tail -0f $LOGS_FILE &
      TAIL_PID=$!
      trap 'kill $TAIL_PID; log "Closing logs..."; return 0' INT
      wait $TAIL_PID
    fi
    if [[ $CHECK_MONITORING ]]; then
      log "waiting 30 seconds before checking monitoring..."
      sleep 30
      if ! check_monitoring; then
        log "Monitoring failed, it seems the application is not well started !"
        return 1
      fi
    fi
  fi
  return 0
}

# stop the tomcat if it is running, return false in case of error
function stop_tomcat {
  if ! check_application; then
    log "Invalid application name for stopping tomcat !"
    return 1
  fi
  log "Stopping tomcat for $APP_NAME..."
  if ! is_app_allowed_on_host; then
    log "$APP_NAME is not allowed on this host ($HOST). Doing nothing."
    return 0
  fi
  if is_tomcat_running; then
    export CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
    export CATALINA_PID="$CATALINA_BASE/catalina.pid"
    $CATALINA_HOME/bin/catalina.sh stop 10 -force;
    log "Tomcat stopped"
  else
    log "Tomcat is not running, not stopping it"
  fi
  return 0
}

# restart the tomcat
function restart_tomcat {
  if ! check_application; then
    log "Invalid application name for restarting tomcat !"
    return 1
  fi
  log "Re-starting tomcat for $APP_NAME..."
  if ! is_app_allowed_on_host; then
    log "$APP_NAME is not allowed on this host ($HOST). Doing nothing."
    return 0
  fi
  stop_tomcat
  start_tomcat
  return 0
}

# start multiple tomcat instances at once, return false in case of error
function start_all_tomcats {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for starting all tomcat !"
    return 1
  fi
  log "Starting tomcat for $APP_LIST..."
  APPS_OK=""
  APPS_NOK=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    if start_tomcat; then
      APPS_OK+="$APP_NAME,"
    else
      APPS_NOK+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_OK ]] && log "Finished ! Start succeeded for : $APPS_OK"
  if [[ -n $APPS_NOK ]]; then
    log "Start failed for : $APPS_NOK"
    return 1
  fi
  return 0
}

# stop multiple tomcat instances at once, return false in case of error
function stop_all_tomcats {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for stopping all tomcat !"
    return 1
  fi
  log "Stopping tomcat for $APP_LIST..."
  APPS_OK=""
  APPS_NOK=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    if stop_tomcat; then
      APPS_OK+="$APP_NAME,"
    else
      APPS_NOK+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_OK ]] && log "Finished ! Stop succeeded for : $APPS_OK"
  if [[ -n $APPS_NOK ]]; then
    log "Stop failed for : $APPS_NOK"
    return 1
  fi
  return 0
}

# restart multiple tomcat instances at once, return false in case of error
function restart_all_tomcats {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for re-starting all tomcat !"
    return 1
  fi
  log "Re-Starting tomcat for $APP_LIST..."
  APPS_OK=""
  APPS_NOK=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    if restart_tomcat; then
      APPS_OK+="$APP_NAME,"
    else
      APPS_NOK+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_OK ]] && log "Finished ! Re-Start succeeded for : $APPS_OK"
  if [[ -n $APPS_NOK ]]; then
    log "Re-Start failed for : $APPS_NOK"
    return 1
  fi
  return 0
}

# update the tomcat conf directory with the content of an archive stored in nexus
# always use the 'RELEASE' version
function update_tomcat_conf {
  if ! check_application; then
    log "Invalid application name for updating tomcat configuration !"
    return 1
  fi
  if [[ -z $ENVIRONMENT ]]; then
    log "Missing environment for updating tomcat configuration !"
    return 1
  fi
  log "Updating tomcat configuration for $APP_NAME on $ENVIRONMENT"
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  CONF_DIR="$CATALINA_BASE/conf"
  CONF_DIR_BAK="$CATALINA_BASE/conf.bak"
  CONF_ARCHIVE="$CATALINA_BASE/conf.tar.gz"
  [[ -f $CONF_ARCHIVE ]] && rm -f $CONF_ARCHIVE
  nexus_opts
  if ! $NEXUS -a download -o $CONF_ARCHIVE -i $APP_NAME-tomcat-conf -v RELEASE -e tar.gz -c $ENVIRONMENT -s $NEXUS_OPTS || [[ ! -s $CONF_ARCHIVE ]]; then
    rm -f $CONF_ARCHIVE
    return 1
  fi
  rm -rf $CONF_DIR_BAK
  mv $CONF_DIR $CONF_DIR_BAK
  mkdir $CONF_DIR 
  if ! tar -C $CONF_DIR -xzf $CONF_ARCHIVE; then
    rm -f $CONF_ARCHIVE
    rm -rf $CONF_DIR
    mv $CONF_DIR_BAK $CONF_DIR
    return 1
  fi
  rm -f $CONF_ARCHIVE
  rm -rf $CONF_DIR_BAK
  return 0
}

# update the tomcat configuration and restart it
function update_tomcat_conf_and_restart {
  if ! update_tomcat_conf; then
    log "Failed to update the tomcat configuration !"
    return 1
  fi
  if ! restart_tomcat; then
    log "Failed to restart the tomcat instance !"
    return 1
  fi
  return 0
}

# update conf and restart multiple tomcats at once
function update_all_tomcats_conf_and_restart {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for updating conf and re-starting all tomcat !"
    return 1
  fi
  log "Updating tomcat configuration and re-starting tomcat for $APP_LIST on $ENVIRONMENT..."
  APPS_OK=""
  APPS_NOK=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    if update_tomcat_conf_and_restart; then
      APPS_OK+="$APP_NAME,"
    else
      APPS_NOK+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_OK ]] && log "Finished ! Update conf and restart succeeded for : $APPS_OK"
  if [[ -n $APPS_NOK ]]; then
    log "Update conf and restart failed for : $APPS_NOK"
    return 1
  fi
  return 0
}

# resolve APP_VERSION to its real version number if it is RELEASE or LATEST
function resolve_version {
  if [[ $APP_VERSION == "LATEST" || $APP_VERSION == "RELEASE" ]]; then
    log "Resolving version number for $APP_NAME - $APP_VERSION..."
    REAL_VERSION=`$NEXUS -a metadata -m version -i $APP_NAME -v $APP_VERSION -e war -q`
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
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  INCOMING_DIR="$CATALINA_BASE/incoming"
  INCOMING_FILE="$INCOMING_DIR/ROOT.war"
  [[ -d $INCOMING_DIR ]] && rm -rf $INCOMING_DIR
  mkdir -p $INCOMING_DIR
  if [[ -n $WAR_FILE && -s $WAR_FILE ]]; then
    log "Using local WAR file : $WAR_FILE"
    cp $WAR_FILE $INCOMING_FILE
  else
    nexus_opts
    if ! $NEXUS -a download -o $INCOMING_FILE -i $APP_NAME -v $APP_VERSION -e war -s $NEXUS_OPTS || [[ ! -s $INCOMING_FILE ]]; then
      rm -rf $INCOMING_DIR
      return 1
    fi
  fi
  return 0
}

# deploy a web application, with a full stop/start of the tomcat
function deploy_webapp {
  if [[ $FORCE_DIRECTORY_CREATION ]]; then
    if ! create_tomcat_dir_structure; then
      log "Failed to force directory structure creation for $APP_NAME !"
      return 1
    fi
  fi
  if ! check_application; then
    log "Invalid application name for deploying !"
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
    log "Error while retrieving WAR file. Invalid application name and/or version ?"
    return 1
  fi
  if [[ $FORCE_CONFIGURATION_UPDATE ]]; then
    if ! update_tomcat_conf; then
      log "Error while updating tomcat configuration !"
      return 1
    fi
  fi
  if ! is_app_allowed_on_host; then
    log "$APP_NAME is not allowed on this host ($HOST). Doing nothing."
    return 0
  fi
  if ! stop_tomcat; then
    log "Failed to stop tomcat !"
    return 1
  fi
  CATALINA_BASE="$WEBAPPS_BASE/$APP_NAME"
  rm -rf $CATALINA_BASE/webapps
  mv $CATALINA_BASE/incoming $CATALINA_BASE/webapps
  rm -rf $CATALINA_BASE/work
  mkdir $CATALINA_BASE/work
  if ! start_tomcat; then
    log "Failed to start tomcat !"
    return 1
  fi
  return 0
}

# deploy multiple web applications at once, return false in case of error
function deploy_all_webapps {
  if [[ -z $APP_LIST ]]; then
    log "Missing application list for deploying all tomcat !"
    return 1
  fi
  log "Deploying $APP_LIST - $APP_VERSION..."
  if [[ ! ($APP_VERSION == "LATEST" || $APP_VERSION == "RELEASE") ]]; then
    log "When deploying all applications, the only supported versions are 'LATEST' or 'RELEASE' !"
    return 1
  fi
  APP_VERSION_BAK=$APP_VERSION
  APPS_OK=""
  APPS_NOK=""
  for APP_NAME in `echo $APP_LIST | tr "," " "`; do
    APP_VERSION=$APP_VERSION_BAK
    if deploy_webapp; then
      APPS_OK+="$APP_NAME,"
    else
      APPS_NOK+="$APP_NAME,"
    fi
    wait
  done
  [[ -n $APPS_OK ]] && log "Finished ! Deploying succeeded for : $APPS_OK"
  if [[ -n $APPS_NOK ]]; then
    log "Deploying failed for : $APPS_NOK"
    return 1
  fi
  return 0
}

##########
# Script #
##########

# extract options
while getopts ":a:l:n:v:e:f:w:hcdmiqt" opt; do
  case $opt in
    a)
      ACTION=$OPTARG
      ;;
    l)
      APP_LIST=$OPTARG
      ;;
    n)
      APP_NAME=$OPTARG
      ;;
    v)
      APP_VERSION=$OPTARG
      ;;
    e)
      ENVIRONMENT=$OPTARG
      ;;
    f)
      WAR_FILE=$OPTARG
      ;;
    c)
      FORCE_CONFIGURATION_UPDATE=true
      ;;
    d)
      FORCE_DIRECTORY_CREATION=true
      ;;
    m)
      CHECK_MONITORING=true
      ;;
    w)
      WAIT_DURATION=$OPTARG
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
    create_tomcat_dir_structure
    ;;
  init-all)
    create_all_tomcats_dir_structure
    ;;
  status) 
    is_tomcat_running
    ;;
  status-all)
    are_all_tomcats_running
    ;;
  start) 
    start_tomcat
    ;;
  start-all)
    start_all_tomcats
    ;;
  stop)
    stop_tomcat
    ;;
  stop-all)
    stop_all_tomcats
    ;;
  restart)
    restart_tomcat
    ;;
  restart-all)
    restart_all_tomcats
    ;;
  deploy)
    deploy_webapp
    ;;
  deploy-all)
    deploy_all_webapps
    ;;
  update-conf)
    update_tomcat_conf_and_restart
    ;;
  update-conf-all)
    update_all_tomcats_conf_and_restart
    ;;
  monitoring)
    check_monitoring
    ;;
  *)
    echo "Invalid action $ACTION"
    usage
    ;;
esac

exit $?

