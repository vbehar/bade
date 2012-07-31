#!/bin/bash
#
# BaDe - The Bash Deployer
#
# BaDe Nexus : Manipulate (and download) artifacts from the Nexus Repository Manager
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

# load the configuration file
CONF_FILE="$PRGDIR/bade-nexus.conf"
if [[ -f $CONF_FILE ]]; then
  source $CONF_FILE
else
  echo "Configuration file for Nexus ($CONF_FILE) could not be found !"
  exit 1
fi

#############
# Functions #
#############

# display the script usage
function usage {
  echo "BaDe (The Bash Deployer) for Nexus (Repository Manager) : manipulate nexus artifacts"
  echo "Usage :"
  echo "  $0 -a metadata -m METADATA -i ARTIFACT_ID -v ARTIFACT_VERSION [-e ARTIFACT_EXTENSION] [-c ARTIFACT_CLASSIFIER] [-q] [-t]"
  echo "     display the metadata value ('-q' : quiet mode, only display the metadata value)"
  echo "     ex: $0 -a metadata -m version -i my-app -v 1.0.0 -e war -q"
  echo "  $0 -a download -o OUTPUT_FILE -i ARTIFACT_ID -v ARTIFACT_VERSION [-e ARTIFACT_EXTENSION] [-c ARTIFACT_CLASSIFIER] [-s] [-q] [-t]"
  echo "     download the artifact ('-s' : add checksum verification)"
  echo "     ex: $0 -a download -o /tmp/my-app-1.0.0.war -i my-app -v 1.0.0 -e war -s"
  echo "  $0 -a checksum -f FILE -i ARTIFACT_ID -v ARTIFACT_VERSION [-e ARTIFACT_EXTENSION] [-c ARTIFACT_CLASSIFIER] [-q] [-t]"
  echo "     validate the checksum of the given file"
  echo "     ex: $0 -a checksum -f /tmp/my-app-1.0.0.war -i my-app -v 1.0.0 -e war"
  echo "Options : "
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

# check that the expected configuration variables are set
function check_configuration {
  local CONF_IS_VALID=0
  for CONF_ELEM in NEXUS_HOST REPOSITORY_RELEASE REPOSITORY_SNAPSHOT GROUP_ID
  do
    if [[ -z ${!CONF_ELEM} ]]; then
      log "$CONF_ELEM is not configured ! Please fix $CONF_FILE first."
      CONF_IS_VALID=1
    fi
  done 
  return $CONF_IS_VALID
}

# echoes the metadata value
function get_artifact_metadata {
  log "Retrieving artifact metadata $METADATA for $ARTIFACT_ID - $ARTIFACT_VERSION..."
  if [[ -z $METADATA || -z $ARTIFACT_ID || -z $ARTIFACT_VERSION ]]; then
    log "metadata, artifactId and artifactVersion are all mandatory !"
    return 1
  fi
  if [[ $ARTIFACT_VERSION == "LATEST" || $ARTIFACT_VERSION =~ ^(.*)-SNAPSHOT$ ]]; then
    local REPOSITORY=$REPOSITORY_SNAPSHOT
  else
    local REPOSITORY=$REPOSITORY_RELEASE
  fi
  local METADATA_URL="$NEXUS_HOST/service/local/artifact/maven/resolve?r=$REPOSITORY&g=$GROUP_ID&a=$ARTIFACT_ID&v=$ARTIFACT_VERSION"
  [[ -n $ARTIFACT_EXTENSION ]] && METADATA_URL+="&e=$ARTIFACT_EXTENSION"
  [[ -n $ARTIFACT_CLASSIFIER ]] && METADATA_URL+="&c=$ARTIFACT_CLASSIFIER"
  local METADATA_FILE="metadata-$ARTIFACT_ID-$ARTIFACT_VERSION.xml"
  rm -f $METADATA_FILE
  if ! wget -q -O $METADATA_FILE "$METADATA_URL" || [[ ! -s $METADATA_FILE ]]; then
    log "Failed to retrieve metadata file !"
    rm -f $METADATA_FILE
    return 1
  fi
  log "$METADATA : "
  cat $METADATA_FILE | grep $METADATA | sed "s/^[ ]*<$METADATA>\(.*\)<\/$METADATA>[ ]*$/\1/g"
  rm -f $METADATA_FILE
  return 0
}

# check if the SHA-1 of the downloaded WAR file matches the one calculated by nexus
function check_sha1 {
  log "Checking SHA-1 validity of $OUTPUT_FILE against $ARTIFACT_ID - $ARTIFACT_VERSION..."
  if [[ -z $FILE || -z $ARTIFACT_ID || -z $ARTIFACT_VERSION ]]; then
    log "file, artifactId and artifactVersion are all mandatory !"
    return 1
  fi
  if [[ ! -s $FILE ]]; then
    log "$FILE does not exists or is empty !"
    return 1
  fi
  local QUIET_BAK=$QUIET
  QUIET=true
  METADATA="sha1"
  EXPECTED_SHA1=`get_artifact_metadata`
  QUIET=$QUIET_BAK
  if [[ $? -ne 0 || -z $EXPECTED_SHA1 ]]; then
    log "Unable to retrieve expected SHA-1 !"
    return 1
  fi
  ACTUAL_SHA1=`openssl sha1 $FILE`
  if [[ $? -ne 0 || -z $ACTUAL_SHA1 ]]; then
    log "Unable to calculate actual SHA-1 !"
    return 1
  fi
  if [[ $ACTUAL_SHA1 =~ ^SHA1\(.*\)=\ ${EXPECTED_SHA1}$ ]]; then
    log "SHA-1 is valid !"
    return 0
  else
    log "SHA-1 does not match !"
    return 1
  fi
}

# download the artifact from nexus, return false in case of error
function download_artifact {
  log "Downloading artifact for $ARTIFACT_ID - $ARTIFACT_VERSION to $OUTPUT_FILE..."
  if [[ -z $OUTPUT_FILE || -z $ARTIFACT_ID || -z $ARTIFACT_VERSION ]]; then
    log "outputFile, artifactId and artifactVersion are all mandatory !"
    return 1
  fi
  if [[ $ARTIFACT_VERSION == "LATEST" || $ARTIFACT_VERSION =~ ^(.*)-SNAPSHOT$ ]]; then
    local REPOSITORY=$REPOSITORY_SNAPSHOT
  else
    local REPOSITORY=$REPOSITORY_RELEASE
  fi
  local ARTIFACT_URL="$NEXUS_HOST/service/local/artifact/maven/content?r=$REPOSITORY&g=$GROUP_ID&a=$ARTIFACT_ID&v=$ARTIFACT_VERSION"
  [[ -n $ARTIFACT_EXTENSION ]] && ARTIFACT_URL+="&e=$ARTIFACT_EXTENSION"
  [[ -n $ARTIFACT_CLASSIFIER ]] && ARTIFACT_URL+="&c=$ARTIFACT_CLASSIFIER"
  [[ -f $OUTPUT_FILE ]] && rm -f $OUTPUT_FILE
  if ! wget -q -O $OUTPUT_FILE "$ARTIFACT_URL" || [[ ! -s $OUTPUT_FILE ]]; then
    log "Failed to download artifact !"
    return 1
  fi
  if [[ $CHECKSUM_VERIFICATION ]]; then
    FILE=$OUTPUT_FILE
    if ! check_sha1; then
      log "SHA1 of downloaded artifact is not valid !"
      rm -f $OUTPUT_FILE
      return 1
    fi
  fi
  log "File successfully downloaded to $OUTPUT_FILE"
  return 0
}

##########
# Script #
##########

# extract options
while getopts ":a:i:v:e:c:m:f:o:hqts" opt; do
  case $opt in
    a)
      ACTION=$OPTARG
      ;;
    i)
      ARTIFACT_ID=$OPTARG
      ;;
    v)
      ARTIFACT_VERSION=$OPTARG
      ;;
    e)
      ARTIFACT_EXTENSION=$OPTARG
      ;;
    c)
      ARTIFACT_CLASSIFIER=$OPTARG
      ;;
    m)
      METADATA=$OPTARG
      ;;
    f)
      FILE=$OPTARG
      ;;
    o)
      OUTPUT_FILE=$OPTARG
      ;;
    s)
      CHECKSUM_VERIFICATION=true
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

# make sure the configuration is set up
if ! check_configuration; then
  echo "Configuration is not properly set up. Exiting !"
  exit 1
fi

# do the job !
case "$ACTION" in
  metadata) 
    get_artifact_metadata
    ;;
  download) 
    download_artifact
    ;;
  checksum)
    check_sha1
    ;;
  *)
    echo "Invalid action $ACTION"
    usage
    exit 1
    ;;
esac

exit $?

