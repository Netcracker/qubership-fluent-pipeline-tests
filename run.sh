#!/bin/sh

# For local tests
#FLUENTBIT_IMAGE="fluent/fluent-bit:3.2.2"
#FLUENTD_IMAGE="ghcr.io/netcracker/qubership-fluentd:main"
#FLUENT_PIPELINE_REPLACER_IMAGE="ghcr.io/netcracker/qubership-fluent-pipeline-tests:main"

#INT_TESTS_IGNORE="nginx-ingress.log.json,airflow.log.json"
#TEST_HOME_PATH="/mnt/c/Repositories/Git/logging/logging-operator"

TEST_HOME_PATH="/builds/${CI_PROJECT_PATH}"
TEST_CONTENT_PATH="test"

# Use sed to copy data from test data in files that fluent should read
add_lines() {
  input_file=$1
  output_file=$2
  echo "emulate logs generation in ${output_file} file (data will copy from ${input_file})"
  sed '' ${input_file} >>${output_file}
}

###################################################################################################
# Run FluentD DaemonSet test logic
###################################################################################################
run_fluentd_test_logic() {
  local FLD_DOCKER_NAME="fluentd"
  local CFG_TIMEOUT="5"
  local PARSE_TIMEOUT="80"

  # Remove test directories from previous run
  echo "=> Prepare test environment and test data"
  rm -rf ${TEST_CONTENT_PATH}

  # Create test directories
  mkdir -p \
    ${TEST_CONTENT_PATH}/config/ \
    ${TEST_CONTENT_PATH}/logs/var/log/audit/ \
    ${TEST_CONTENT_PATH}/logs/var/log/kubernetes/audit/ \
    ${TEST_CONTENT_PATH}/output/

  # Grant permissions
  chmod -R ugo+rw ${TEST_CONTENT_PATH}/
  chmod -R u+x fluent-pipeline-test/scripts
  chmod -R ugo+r \
    fluent-pipeline-test/output-logs/fluentd/ \
    controllers/fluentd/fluentd.configmap/

  # prepare fluent bit configs
  echo "=> Prepare FluentD configurations"

  docker run --rm --name fluent-config-replacer \
    -v ${TEST_HOME_PATH}/controllers/fluentd/fluentd.configmap/:/config-templates.d:ro \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/config/:/configuration.d:rw \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/:/testdata:rw \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/assets/fluentd.yaml:/assets/fluentd.yaml:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/testdata/:/logs:rw \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -agent fluentd \
    -cr /assets/fluentd.yaml \
    -stage prepare \
    -loglevel info \
    -ignore ${INT_TESTS_IGNORE}

  # wait until prepare container stop
  echo "=> Waiting for stop container rendered FluentD configuration (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  # run FluentD
  echo "=> Run FluentD to read, parse and output processed logs"
  docker run --privileged -d --name ${FLD_DOCKER_NAME} \
    -e HOSTNAME=fake-fluent \
    -e K8S_NODE_NAME=fake-node \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/config/:/fluentd/etc \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/var/log/:/var/log:rw \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/output/:/fluentd-output:rw \
    ${FLUENTD_IMAGE}

  echo "=> Waiting for FluentD start (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  echo "=> Start print prepared test data in logs"
  add_lines fluent-pipeline-test/testdata/logs/kubernetes/audit/audit.log ${TEST_CONTENT_PATH}/logs/var/log/kubernetes/audit/audit.log
  add_lines fluent-pipeline-test/testdata/logs/audit/audit.log ${TEST_CONTENT_PATH}/logs/var/log/audit/audit.log
  add_lines fluent-pipeline-test/testdata/logs/system/syslog ${TEST_CONTENT_PATH}/logs/var/log/syslog
  add_lines fluent-pipeline-test/testdata/logs/system/messages ${TEST_CONTENT_PATH}/logs/var/log/messages
  add_lines fluent-pipeline-test/testdata/logs/system/journal ${TEST_CONTENT_PATH}/logs/var/log/journal

  echo "=> Waiting until FluentD process all logs (${PARSE_TIMEOUT} seconds)"
  sleep ${PARSE_TIMEOUT}

  echo "=> Stop and remove FluentD docker container"
  docker logs ${FLD_DOCKER_NAME}
  docker stop ${FLD_DOCKER_NAME}

  echo "=> Run the docker container to analyze FluentD parsed logs and compare with expected data"
  docker run --rm --name fluent-pipeline-test \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/output/:/output-logs/actual:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/output-logs/fluentd/:/output-logs/expected:ro \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -stage test \
    -agent fluentd \
    -ignore ${INT_TESTS_IGNORE}
}

###################################################################################################
# Run FluentBit DaemonSet test logic
###################################################################################################
run_fluentbit_test_logic() {
  local FLB_DOCKER_NAME="fluent-bit"
  local CFG_TIMEOUT="5"
  local PARSE_TIMEOUT="80"

  # Remove test directories from previous run
  echo "=> Prepare test environment and test data"
  rm -rf ${TEST_CONTENT_PATH}

  # Create test directories
  mkdir -p \
    ${TEST_CONTENT_PATH}/config/ \
    ${TEST_CONTENT_PATH}/logs/var/log/audit/ \
    ${TEST_CONTENT_PATH}/logs/var/log/kubernetes/audit/ \
    ${TEST_CONTENT_PATH}/output/

  # Grant permissions
  chmod -R ugo+rw ${TEST_CONTENT_PATH}/
  chmod -R u+x fluent-pipeline-test/scripts
  chmod -R ugo+r \
    fluent-pipeline-test/output-logs/fluentbit/ \
    controllers/fluentbit/fluentbit.configmap/

  # prepare fluent bit configs
  echo "=> Prepare FluentBit configurations"

  docker run --rm --name fluent-config-replacer \
    -v ${TEST_HOME_PATH}/controllers/fluentbit/fluentbit.configmap/:/config-templates.d:ro \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/config/:/configuration.d:rw \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/:/testdata:rw \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/assets/fluentbit.yaml:/assets/fluentbit.yaml:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/testdata/:/logs:rw \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -agent fluentbit \
    -cr /assets/fluentbit.yaml \
    -stage prepare \
    -loglevel info \
    -ignore ${INT_TESTS_IGNORE}

  # wait until prepare container stop
  echo "=> Waiting for stop container rendered FluentBit configuration (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  # run fluent bit
  echo "=> Run FluentBit to read, parse and output processed logs"
  docker run --rm -d --name ${FLB_DOCKER_NAME} \
    -e HOSTNAME=fake-fluent \
    -e NODE_NAME=fake-node \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/config/:/fluent-bit/etc \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/var/log/:/var/log:rw \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/output/:/fluentbit-output:rw \
    ${FLUENTBIT_IMAGE}

  echo "=> Waiting for FluentBit start (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  echo "=> Start print prepared test data in logs"
  add_lines fluent-pipeline-test/testdata/logs/kubernetes/audit/audit.log ${TEST_CONTENT_PATH}/logs/var/log/kubernetes/audit/audit.log
  add_lines fluent-pipeline-test/testdata/logs/audit/audit.log ${TEST_CONTENT_PATH}/logs/var/log/audit/audit.log
  add_lines fluent-pipeline-test/testdata/logs/system/syslog ${TEST_CONTENT_PATH}/logs/var/log/syslog
  add_lines fluent-pipeline-test/testdata/logs/system/messages ${TEST_CONTENT_PATH}/logs/var/log/messages
  add_lines fluent-pipeline-test/testdata/logs/system/journal ${TEST_CONTENT_PATH}/logs/var/log/journal

  echo "=> Waiting until FluentBit process all logs (${PARSE_TIMEOUT} seconds)"
  sleep ${PARSE_TIMEOUT}

  echo "=> Stop and remove FluentBit docker container"
  docker logs ${FLB_DOCKER_NAME}
  docker stop ${FLB_DOCKER_NAME}

  echo "=> Run the docker container to analyze FluentBit parsed logs and compare with expected data"
  docker run --rm --name fluent-pipeline-test \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/output/:/output-logs/actual:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/output-logs/fluentbit/:/output-logs/expected:ro \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -agent fluentbit \
    -stage test \
    -ignore ${INT_TESTS_IGNORE}
}

###################################################################################################
# Run FluentBit DaemonSet + FluentBit StatefulSet (aka HA deployment) test logic
###################################################################################################
run_fluentbit_ha_test_logic() {
  local FLB_FRW_DOCKER_NAME="fluent-bit-forwarder"
  local FLB_AGR_DOCKER_NAME="fluent-bit-aggregator"
  local CFG_TIMEOUT="5"
  local PARSE_TIMEOUT="80"

  # Remove test directories from previous run
  echo "=> Prepare test environment and test data"
  rm -rf ${TEST_CONTENT_PATH}

  # Create test directories
  mkdir -p \
    ${TEST_CONTENT_PATH}/forwarder-config/ \
    ${TEST_CONTENT_PATH}/aggregator-config/ \
    ${TEST_CONTENT_PATH}/logs/var/log/audit/ \
    ${TEST_CONTENT_PATH}/logs/var/log/kubernetes/audit/ \
    ${TEST_CONTENT_PATH}/output/

  # Grant permissions
  chmod -R ugo+rw ${TEST_CONTENT_PATH}/
  chmod -R u+x fluent-pipeline-test/scripts
  chmod -R ugo+r \
    fluent-pipeline-test/output-logs/fluentbit/ \
    controllers/fluentbit-forwarder-aggregator/forwarder.configmap/ \
    controllers/fluentbit-forwarder-aggregator/aggregator.configmap/

  # prepare fluent bit configs
  echo "=> Prepare FluentBit configurations"

  docker run --rm --name fluent-config-replacer \
    -v ${TEST_HOME_PATH}/controllers/fluentbit-forwarder-aggregator/forwarder.configmap/:/config-templates.d:ro \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/forwarder-config/:/configuration.d:rw \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/:/testdata:rw \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/assets/fluentbit-ha.yaml:/assets/fluentbit-ha.yaml:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/testdata/:/logs:rw \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -agent fluentbitha \
    -cr /assets/fluentbit-ha.yaml \
    -stage prepare \
    -loglevel info \
    -ignore ${INT_TESTS_IGNORE}

  # wait until prepare container stop
  echo "=> Waiting for stop container rendered FluentBit configuration (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  docker run --rm --name fluent-config-replacer \
    -v ${TEST_HOME_PATH}/controllers/fluentbit-forwarder-aggregator/aggregator.configmap/:/config-templates.d:ro \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/aggregator-config/:/configuration.d:rw \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/:/testdata:rw \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/assets/fluentbit-ha.yaml:/assets/fluentbit-ha.yaml:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/testdata/:/logs:rw \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -agent fluentbitha \
    -cr /assets/fluentbit-ha.yaml \
    -stage prepare \
    -loglevel info \
    -ignore ${INT_TESTS_IGNORE}

  # wait until prepare container stop
  echo "=> Waiting for stop container rendered FluentBit configuration (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  # run fluent bit
  echo "=> Run FluentBit to read, parse and output processed logs"

  docker network create fluent-net

  docker run --rm -d --name ${FLB_AGR_DOCKER_NAME} \
    --network=fluent-net \
    -e HOSTNAME=fake-fluent \
    -e NODE_NAME=fake-node \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/aggregator-config/:/fluent-bit/etc \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/output/:/fluentbit-output:rw \
    ${FLUENTBIT_IMAGE}

  echo "=> Waiting for FluentBit aggregator start (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  docker run --rm -d --name ${FLB_FRW_DOCKER_NAME} \
    --network=fluent-net \
    -e HOSTNAME=fake-fluent \
    -e NODE_NAME=fake-node \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/forwarder-config/:/fluent-bit/etc \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/logs/var/log/:/var/log:rw \
    ${FLUENTBIT_IMAGE}

  echo "=> Waiting for FluentBit forwarder start (${CFG_TIMEOUT} seconds)"
  sleep ${CFG_TIMEOUT}

  echo "=> Start print prepared test data in logs"
  add_lines fluent-pipeline-test/testdata/logs/kubernetes/audit/audit.log ${TEST_CONTENT_PATH}/logs/var/log/kubernetes/audit/audit.log
  add_lines fluent-pipeline-test/testdata/logs/audit/audit.log ${TEST_CONTENT_PATH}/logs/var/log/audit/audit.log
  add_lines fluent-pipeline-test/testdata/logs/system/syslog ${TEST_CONTENT_PATH}/logs/var/log/syslog
  add_lines fluent-pipeline-test/testdata/logs/system/messages ${TEST_CONTENT_PATH}/logs/var/log/messages
  add_lines fluent-pipeline-test/testdata/logs/system/journal ${TEST_CONTENT_PATH}/logs/var/log/journal

  echo "=> Waiting until FluentBit process all logs (${PARSE_TIMEOUT} seconds)"
  sleep ${PARSE_TIMEOUT}

  echo "=> Print FlintBit forwarder logs"
  docker logs ${FLB_FRW_DOCKER_NAME}

  echo "=> Print FlintBit aggregator logs"
  docker logs ${FLB_AGR_DOCKER_NAME}

  echo "=> Stop and remove FluentBit docker container"
  docker stop ${FLB_FRW_DOCKER_NAME}
  docker stop ${FLB_AGR_DOCKER_NAME}

  docker network rm fluent-net

  echo "=> Run the docker container to analyze FluentBit parsed logs and compare with expected data"
  docker run --rm --name fluent-pipeline-test \
    -v ${TEST_HOME_PATH}/${TEST_CONTENT_PATH}/output/:/output-logs/actual:ro \
    -v ${TEST_HOME_PATH}/fluent-pipeline-test/output-logs/fluentbit/:/output-logs/expected:ro \
    ${FLUENT_PIPELINE_REPLACER_IMAGE} \
    -agent fluentbitha \
    -stage test \
    -ignore ${INT_TESTS_IGNORE}
}

###################################################################################################
# Entrypoint
###################################################################################################

case $1 in

'fluentd')
  run_fluentd_test_logic
  ;;

'fluentbit')
  run_fluentbit_test_logic
  ;;

'fluentbit-ha')
  run_fluentbit_ha_test_logic
  ;;

esac
