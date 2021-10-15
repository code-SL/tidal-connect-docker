#!/bin/bash

log() {
  script=$(basename "$0")
  echo "$(/bin/date) ${HOSTNAME} ${script}[$$]: [$1]: $2"
}

running_environment()
{
  echo "Running environment: "
  echo "  FRIENDLY_NAME:            ${FRIENDLY_NAME}"
  echo "  MODEL_NAME:               ${MODEL_NAME}"
  echo "  BEOCREATE_SYMLINK_FOLDER: ${BEOCREATE_SYMLINK_FOLDER}"
  echo "  DOCKER_DNS:               ${DOCKER_DNS}"
  echo "  DOCKER_IMAGE:             ${DOCKER_IMAGE}"
  echo "  BUILD_OR_PULL:            ${BUILD_OR_PULL}"
  echo "  PWD:                      ${PWD}"
  echo ""
}

usage()
{
  echo "$0 installs TIDAL Connect on your Raspberry Pi."
  echo ""
  echo "Usage: "
  echo ""
  echo "  [FRIENDLY_NAME=<FRIENDLY_NAME>] \\"
  echo "  [MODEL_NAME=<MODEL_NAME> ] \\"
  echo "  [BEOCREATE_SYMLINK_FOLDER=<BEOCREATE_SYMLINK_FOLDER> ] \\"
  echo "  [DOCKER_DNS=<DOCKER_DNS> ] \\"
  echo "  $0 \\"
  echo "    [-f <FRIENDLY_NAME>] \\"
  echo "    [-m <MODEL_NAME>] \\"
  echo "    [-b <BEOCREATE_SYMLINK_FOLDER>] \\"
  echo "    [-d <DOCKER_DNS>] \\"
  echo "    [-i <Docker Image>] \\"
  echo "    [-p <build|pull>]"
  echo ""
  echo "Defaults:"
  echo "  FRIENDLY_NAME:            ${FRIENDLY_NAME_DEFAULT}"
  echo "  MODEL_NAME:               ${MODEL_NAME_DEFAULT}"
  echo "  BEOCREATE_SYMLINK_FOLDER: ${BEOCREATE_SYMLINK_FOLDER_DEFAULT}"
  echo "  DOCKER_DNS:               ${DOCKER_DNS_DEFAULT}"
  echo "  DOCKER_IMAGE:             ${DOCKER_IMAGE_DEFAULT}"
  echo "  BUILD_OR_PULL:            ${BUILD_OR_PULL_DEFAULT}"
  echo ""

  echo "Example: "
  echo "  BUILD_OR_PULL=build \\"
  echo "  DOCKER_IMAGE=tidal-connect:latest \\"
  echo "  $0"
  echo ""

  running_environment

  echo "Please note that command line arguments "
  echo "take precedence over environment variables,"
  echo "which take precedence over defaults."
  echo ""
}

# define defaults
FRIENDLY_NAME_DEFAULT=${HOSTNAME}
MODEL_NAME_DEFAULT=${HOSTNAME}
BEOCREATE_SYMLINK_FOLDER_DEFAULT="/opt/beocreate/beo-extensions/tidal"
DOCKER_DNS_DEFAULT="8.8.8.8"
DOCKER_IMAGE_DEFAULT="edgecrush3r/tidal-connect:latest"
BUILD_OR_PULL_DEFAULT="pull"

# override defaults with environment variables, if they have been set
FRIENDLY_NAME=${FRIENDLY_NAME:-${FRIENDLY_NAME_DEFAULT}}
MODEL_NAME=${MODEL_NAME:-${MODEL_NAME_DEFAULT}}
BEOCREATE_SYMLINK_FOLDER=${BEOCREATE_SYMLINK_FOLDER:-${BEOCREATE_SYMLINK_FOLDER_DEFAULT}}
DOCKER_DNS=${DOCKER_DNS:-${DOCKER_DNS_DEFAULT}}
DOCKER_IMAGE=${DOCKER_IMAGE:-${DOCKER_IMAGE_DEFAULT}}
BUILD_OR_PULL=${BUILD_OR_PULL:-${BUILD_OR_PULL_DEFAULT}}

HELP=${HELP:-0}
VERBOSE=${VERBOSE:-0}

# override with command line parameters, if defined
while getopts "hvf:m:b:d:i:p:" option
do
  case ${option} in
    f)
      FRIENDLY_NAME=${OPTARG}
      ;;
    m)
      MODEL_NAME=${OPTARG}
      ;;
    b)
      BEOCREATE_SYMLINK_FOLDER=${OPTARG}
      ;;
    d)
      DOCKER_DNS=${OPTARG}
      ;;
    i)
      DOCKER_IMAGE=${OPTARG}
      ;;
    p)
      BUILD_OR_PULL=${OPTARG}
      ;;
    v)
      VERBOSE=1
      ;;
    h)
      HELP=1
      usage
      exit 0
      ;;
  esac
done

running_environment

log INFO "Pre-flight checks."

log INFO "Checking to see if Docker is running."
docker info &> /dev/null
if [ $? -ne 0 ]
then
  log ERROR "Docker daemon isn't running."
  exit 1
else
  log INFO "Confirmed that Docker daemon is running."
fi

log INFO "Checking to see if Docker image ${DOCKER_IMAGE} exists."
docker inspect --type=image ${DOCKER_IMAGE} &> /dev/null
if [ $? -eq 0 ]
then
  log INFO "Docker image ${DOCKER_IMAGE} exist on the local machine."
  DOCKER_IMAGE_EXISTS=1
else
  log INFO "Docker image ${DOCKER_IMAGE} does not exist on local machine."
  DOCKER_IMAGE_EXISTS=0
fi

# Pull latest image or build Docker image if it doesn't already exist.
if [ ${DOCKER_IMAGE_EXISTS} -eq 0 ]
then
  if [ "${BUILD_OR_PULL}" == "pull" ]
  then
    # Pulling latest image
    log INFO "Pulling docker image ${DOCKER_IMAGE}."
    docker pull ${DOCKER_IMAGE}
    log INFO "Finished pulling docker image ${DOCKER_IMAGE}."
  elif [ "${BUILD_OR_PULL}" == "build" ]
  then
    log INFO "Building docker image."
    cd Docker && \
    DOCKER_IMAGE=${DOCKER_IMAGE} ./build_docker.sh && \
    cd ..
    log INFO "Finished building docker image."
  else
    log ERROR "BUILD_OR_PULL must be set to \"build\" or \"pull\""
    usage
    exit 1
  fi

  docker inspect --type=image ${DOCKER_IMAGE} &> /dev/null
  if [ $? -ne 0 ]
  then
    log ERROR "Docker image ${DOCKER_IMAGE} does not exist on the local machine even after we tried ${BUILD_OR_PULL}ing it."
    log ERROR "Exiting."
    exit 1
  fi
fi

log INFO "Creating .env file."
> Docker/.env
echo "FRIENDLY_NAME=${FRIENDLY_NAME}" >> Docker/.env
echo "MODEL_NAME=${MODEL_NAME}" >> Docker/.env
log INFO "Finished creating .env file."

# Generate docker-compose.yml
log INFO "Generating docker-compose.yml."
eval "echo \"$(cat templates/docker-compose.yml.tpl)\"" > Docker/docker-compose.yml
log INFO "Finished generating docker-compose.yml."

# Enable service
log INFO  "Enabling TIDAL Connect Service."
#cp systemd/tidal.service /etc/systemd/system/
eval "echo \"$(cat templates/tidal.service.tpl)\"" >/etc/systemd/system/tidal.service

systemctl enable tidal.service

log INFO "Finished enabling TIDAL Connect Service."

# Add TIDAL Connect Source to Beocreate
log INFO "Adding TIDAL Connect Source to Beocreate."
if [ -L "${BEOCREATE_SYMLINK_FOLDER}" ]; then
  # Already installed... remove symlink and re-install
  log INFO "TIDAL Connect extension found, removing previous install."
  rm ${BEOCREATE_SYMLINK_FOLDER}
fi

echo  "Adding TIDAL Connect Source to Beocreate UI."
ln -s ${PWD}/beocreate/beo-extensions/tidal ${BEOCREATE_SYMLINK_FOLDER}
log INFO "Finished adding TIDAL Connect Source to Beocreate."

log INFO "Installation Completed."

if [ "$(docker ps -q -f name=docker_tidal-connect)" ]; then
  log INFO "Stopping TIDAL Connect Service."
  ./stop-tidal-service.sh
fi

log INFO "Starting TIDAL Connect Service."
./start-tidal-service.sh

log INFO "Restarting Beocreate 2 Service."
./restart_beocreate2.sh

log INFO "Finished, exiting."
