#!/bin/sh
set -e;

WATCH=0;
PROJ="";
FILTERS="";
USE_DOCKER=0;
RUNNING_IN_PIPELINE=0;
RUN_LOCAL_ENV=0;
TEST_TYPE="";
COVERAGE="";

while [ "$#" -gt 0 ]; do
  case "$1" in
    -w|--watch) WATCH=1; shift 1;;
    --docker) USE_DOCKER=1; shift 1;;
    --cicd) RUNNING_IN_PIPELINE=1; USE_DOCKER=1; shift 1;;
    --filter) FILTERS="--filter ${2}"; shift 2;;
    --unit) FILTERS="--filter Type=Unit"; TEST_TYPE="unit"; shift 1;;
    --integration) FILTERS="--filter Type=Integration"; TEST_TYPE="integration"; RUN_LOCAL_ENV=1; USE_DOCKER=1; shift 1;;
    --e2e) FILTERS="--filter Type=E2E"; TEST_TYPE="e2e"; RUN_LOCAL_ENV=1; USE_DOCKER=1; shift 1;;
    --coverage) COVERAGE="--collect:\"XPlat Code Coverage\" -- DataCollectionRunSettings.DataCollectors.DataCollector.Configuration.Format=opencover"; FILTERS="--filter Type=Unit"; TEST_TYPE="unit"; shift 1;;

    -*) echo "unknown option: $1" >&2; exit 1;;
    *) PROJ=$1; shift 1;;
  esac
done

case "${TEST_TYPE}" in
  "unit")
    if [ ! -d "./test/unit/" ]; then
      echo "No './test/unit/' directory found. Assuming no unit tests exist.";
      exit 0;
    fi
    ;;
  "integration")
    if [ ! -d "./test/integration/" ]; then
      echo "No './test/integration/' directory found. Assuming no integration tests exist.";
      exit 0;
    fi
    ;;
  "e2e")
    if [ ! -d "./test/e2e/" ]; then
      echo "No './test/e2e/' directory found. Assuming no e2e tests exist.";
      exit 0;
    fi
    ;;
esac

if [ $RUN_LOCAL_ENV -eq 1 ]; then
  sh ./cli/start.sh -d;

  echo "Waiting for all Docker services to be healthy or up...";

  MAX_RETRIES=30;
  RETRY_DELAY=2;
  ATTEMPTS=0;

  COMPOSE_FILE="./setup/local/docker-compose.yml";
  PROJECT_NAME="myapp";

  while true; do
    # Extract statuses
    BAD_CONTAINERS=$(docker compose -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" ps --format json | jq -s . | jq -r '.[] | select(.State != "running" and .Health != "healthy") | "\(.Name): \(.State) (\(.Health // "no healthcheck"))"');

    if [ -z "${BAD_CONTAINERS}" ]; then
      echo "All services are up and (if defined) healthy!";
      break;
    fi

    ATTEMPTS=$((ATTEMPTS+1));
    if [ $ATTEMPTS -ge $MAX_RETRIES ]; then
      echo "ERROR: Some services failed to become ready:";
      echo "${BAD_CONTAINERS}";
      docker compose -f "${COMPOSE_FILE}" -p "${PROJECT_NAME}" ps;
      exit 1;
    fi

    sleep $RETRY_DELAY;
  done
else
  docker network create myapp_shared || true;
fi

CMD="dotnet test ${FILTERS} ${COVERAGE} ${PROJ}";

if [ $WATCH -eq 1 ]; then
  if [ -z "$PROJ" ]; then
    echo "In watch mode a project name or path must be provided as argument." >&2; exit 1;
  fi

  CMD="dotnet watch test -q --project ${PROJ} ${FILTERS}";
fi

if [ $USE_DOCKER -eq 1 ]; then
  INTERACTIVE_FLAGS="-it";
  if [ $RUNNING_IN_PIPELINE -eq 1 ]; then
    INTERACTIVE_FLAGS="-i";
  fi

  docker run --rm ${INTERACTIVE_FLAGS} --network=myapp_shared -v "./:/app/" -w "/app/" mcr.microsoft.com/dotnet/sdk:8.0-noble /bin/sh -c "${CMD}";
else
  eval "${CMD}";
fi
