#!/bin/bash

set -x

function get_metadata() {
  # Do not exit on curl error.
  set +e
  key="$1"
  curl -fsS "http://metadata.google.internal/computeMetadata/v1/instance/$key" -H "Metadata-Flavor:Google" 2>/dev/null
  set -e
}

[ -z "$PROJECT_ID" ] && PROJECT_ID=$(get_metadata "attributes/project_id")
[ -z "$PROJECT_ID" ] && PROJECT_ID="projects/rbe-prod-demo"

[ -z "$INSTANCE_NAME" ] && INSTANCE_NAME=$(get_metadata "attributes/instance_name")
[ -z "$INSTANCE_NAME" ] && INSTANCE_NAME="instances/default_instance"

[ -z "$REMOTE_ACCEPT_CACHED" ] && REMOTE_ACCEPT_CACHED=$(get_metadata "attributes/remote_accept_cached")
[ -z "$REMOTE_ACCEPT_CACHED" ] && REMOTE_ACCEPT_CACHED=true

[ -z "$CACHE_TEST_RESULTS" ] && CACHE_TEST_RESULTS=$(get_metadata "attributes/cache_test_results")
[ -z "$CACHE_TEST_RESULTS" ] && CACHE_TEST_RESULTS=true

[ -z "$BUILD_TYPE" ] && BUILD_TYPE=$(get_metadata "attributes/build_type")
[ -z "$BUILD_TYPE" ] && BUILD_TYPE="cpu"

[ -z "$NUM_OF_RUNS" ] && NUM_OF_RUNS=$(get_metadata "attributes/num_of_runs")
[ -z "$NUM_OF_RUNS" ] && NUM_OF_RUNS=1

[ -z "$NUM_OF_MODIFIES" ] && NUM_OF_MODIFIES=$(get_metadata "attributes/num_of_modifies")
[ -z "$NUM_OF_MODIFIES" ] && NUM_OF_MODIFIES=0

[ -z "$NUM_OF_JOBS" ] && NUM_OF_JOBS=$(get_metadata "attributes/num_of_jobs")
[ -z "$NUM_OF_JOBS" ] && NUM_OF_JOBS=500

[ -z "$TF_COMMIT" ] && TF_COMMIT=$(get_metadata "attributes/tf_commit")

[ -z "$TF_REPO" ] && TF_REPO=$(get_metadata "attributes/tf_repo")
[ -z "$TF_REPO" ] && TF_REPO="https://github.com/tensorflow/tensorflow.git"

[ -z "$STACKDRIVER_LOG_FILE" ] && STACKDRIVER_LOG_FILE=/tmp/bazel-tf-log.log

if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  AUTH_CREDENTIALS=" --auth_credentials=$GOOGLE_APPLICATION_CREDENTIALS "
fi


BUILD_LOG=/tmp/build.log

function log_message() {
  msg="$@"
  echo '{"message": "'$msg'"}' >> "$STACKDRIVER_LOG_FILE"
  echo "[$(date)] $msg"
}

function randomly_modify_files() {
  N=$((NUM_OF_MODIFIES/2))
  for f in $(find . -name *.cc | shuf | head -n $N);
  do
    sed -i "1s/^/\/\/ Random string: $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)\n/" "$f"
    echo "$f"
  done

  N=$((NUM_OF_MODIFIES-N))
  for f in $(find . -name *.py | shuf | head -n $N);
  do
    sed -i "1s/^/# Random string: $(cat /dev/urandom | tr -cd 'a-f0-9' | head -c 32)\n/" "$f"
  done
  log_message "Randomly modified $NUM_OF_MODIFIES files"
}

git clone "$TF_REPO" tensorflow
cd tensorflow
if [ -n "$TF_COMMIT" ]; then
  git reset --hard "$TF_COMMIT"
fi

if [ "$BUILD_TYPE" = "cpu" ]; then
  # Run configure.
  export TF_NEED_GCP=0
  export TF_NEED_HDFS=0
  export TF_NEED_CUDA=0
  # PYTHON_BIN_PATH must be set to path of python in exec container
  export PYTHON_BIN_PATH="/usr/bin/python"
  yes "" | ./configure
fi

for ((i=0;i<$NUM_OF_RUNS;i++))
do
  randomly_modify_files
  log_message "Start building TensorFlow $BUILD_TYPE (run $((i+1)) / $NUM_OF_RUNS)"
  unbuffer bazel --bazelrc=/.bazelrc.rbe."$BUILD_TYPE" test --config=remote \
    --remote_accept_cached="$REMOTE_ACCEPT_CACHED" \
    --jobs="$NUM_OF_JOBS" ${AUTH_CREDENTIALS} \
    --cache_test_results="$CACHE_TEST_RESULTS" \
    --remote_instance_name="$PROJECT_ID/$INSTANCE_NAME" \
    -- //tensorflow/... -//tensorflow/lite/... -//tensorflow/contrib/... \
    -//tensorflow/compiler/tests:fft_test_cpu \
    | tee "$BUILD_LOG"
  log_message "Finished building $BUILD_TYPE (run $((i+1)) / $NUM_OF_RUNS)"

  if [ $i -eq 0 ]; then
    local_cache=false
  else
    local_cache=true
  fi
  # Extract the build stats.
  if cat "$BUILD_LOG" | grep 'FAILED: Build did NOT complete successfully' > /dev/null; then
    success=false
  else
    success=true
  fi
  duration=$(cat "$BUILD_LOG" | grep -o 'Elapsed time: [0-9\.]\+' | grep -o '[0-9\.]\+')
  critical=$(cat "$BUILD_LOG" | grep -o 'Critical Path: [0-9\.]\+' | grep -o '[0-9\.]\+')
  actions=$(cat "$BUILD_LOG" | grep 'INFO:.*total actions$' | tail -n1 | grep -o '[0-9]\+ total actions' | grep -o '[0-9]\+')
  if [ -z "$actions" ]; then
    actions=0
  fi
  echo '{ "local_cache": "'$local_cache'", "duration": "'$duration'", "actions": "'$actions'", "build_type": "'$BUILD_TYPE'", "remote_accept_cached": "'$REMOTE_ACCEPT_CACHED'", "num_of_modifies": "'$NUM_OF_MODIFIES'", "success": "'$success'", "critical": "'$critical'" }' >> "$STACKDRIVER_LOG_FILE"
done
