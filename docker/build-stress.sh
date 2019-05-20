#!/bin/bash
#
# This script builds https://github.com/werkt/bazel-stress

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
[ -z "$REMOTE_ACCEPT_CACHED" ] && REMOTE_ACCEPT_CACHED=false

[ -z "$CACHE_TEST_RESULTS" ] && CACHE_TEST_RESULTS=$(get_metadata "attributes/cache_test_results")
[ -z "$CACHE_TEST_RESULTS" ] && CACHE_TEST_RESULTS=true

[ -z "$CLEAN_LOCAL_CACHE" ] && CLEAN_LOCAL_CACHE=$(get_metadata "attributes/clean_local_cache")
[ -z "$CLEAN_LOCAL_CACHE" ] && CLEAN_LOCAL_CACHE=true

[ -z "$NUM_OF_RUNS" ] && NUM_OF_RUNS=$(get_metadata "attributes/num_of_runs")
[ -z "$NUM_OF_RUNS" ] && NUM_OF_RUNS=1

[ -z "$NUM_OF_JOBS" ] && NUM_OF_JOBS=$(get_metadata "attributes/num_of_jobs")
[ -z "$NUM_OF_JOBS" ] && NUM_OF_JOBS=500

[ -z "$SHAMT" ] && SHAMT=$(get_metadata "attributes/shamt")
[ -z "$SHAMT" ] && SHAMT=7

[ -z "$DESIRED_TARGETS" ] && DESIRED_TARGETS=$(get_metadata "attributes/desired_targets")
[ -z "$DESIRED_TARGETS" ] && DESIRED_TARGETS=100000

[ -z "$STACKDRIVER_LOG_FILE" ] && STACKDRIVER_LOG_FILE=/tmp/bazel-tf-log.log

if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  AUTH_CREDENTIALS=" --auth_credentials=$GOOGLE_APPLICATION_CREDENTIALS "
fi

REPO=https://github.com/werkt/bazel-stress.git

BUILD_LOG=/tmp/build.log

function log_message() {
  msg="$@"
  echo '{"message": "'$msg'"}' >> "$STACKDRIVER_LOG_FILE"
  echo "[$(date)] $msg"
}

# Use GOOGLE_APPLICATION_CREDENTIALS to generate the git credentials in order to
# access Google Source Repo.
python /git_cookie_daemon.py --configure-git

git clone "$REPO" bazel-stress
cd bazel-stress

# Setup the WORKSPACE.
cat <<"EOF" >> WORKSPACE
http_archive(
    name = "bazel_toolchains",
    sha256 = "36e5cb9f15543faa195daa9ee9c8a7f0306f6b4f3e407ffcdb9410884d9ac4de",
    strip_prefix = "bazel-toolchains-0.25.0",
    urls = [
        "https://mirror.bazel.build/github.com/bazelbuild/bazel-toolchains/archive/0.25.0.tar.gz",
        "https://github.com/bazelbuild/bazel-toolchains/archive/0.25.0.tar.gz",
    ],
)

load("@bazel_toolchains//rules:rbe_repo.bzl", "rbe_autoconfig")

# Creates a default toolchain config for RBE.
# Use this as is if you are using the rbe_ubuntu16_04 container,
# otherwise refer to RBE docs.
rbe_autoconfig(name = "rbe_default")
EOF

# Fetch the bazelrc.
curl -LO https://raw.githubusercontent.com/bazelbuild/bazel-toolchains/master/bazelrc/.bazelrc

# Generate BUILD file.
bazel run tools:gen -- $SHAMT $DESIRED_TARGETS > BUILD

for ((i=0;i<$NUM_OF_RUNS;i++))
do
  if $CLEAN_LOCAL_CACHE; then
    log_message "Running bazel clean"
    bazel clean
  fi
  log_message "Start building (run $((i+1)) / $NUM_OF_RUNS)"
  unbuffer bazel build \
    --config=remote \
    --remote_accept_cached="$REMOTE_ACCEPT_CACHED" \
    --jobs="$NUM_OF_JOBS" ${AUTH_CREDENTIALS} \
    --cache_test_results="$CACHE_TEST_RESULTS" \
    --remote_instance_name="$PROJECT_ID/$INSTANCE_NAME" \
    :all | tee "$BUILD_LOG"
  log_message "Finished (run $((i+1)) / $NUM_OF_RUNS)"

  if [[ $i -eq 0 ]] || $CLEAN_LOCAL_CACHE; then
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
  echo '{ "local_cache": "'$local_cache'", "duration": "'$duration'", "actions": "'$actions'", "build_type": "'$BUILD_TYPE'", "remote_accept_cached": "'$REMOTE_ACCEPT_CACHED'", "num_of_modifies": "'$NUM_OF_MODIFIES'", "success": "'$success'", "critical": "'$critical'", "clean_local_cache": "'$CLEAN_LOCAL_CACHE'", "cache_test_results": "'$CACHE_TEST_RESULTS'", "repo": "'$REPO'" }' >> "$STACKDRIVER_LOG_FILE"
  python /send_build_stats.py --project_id=$(basename $PROJECT_ID) \
    --build_type=$BUILD_TYPE \
    --remote_accept_cached=$REMOTE_ACCEPT_CACHED \
    --cache_test_results=$CACHE_TEST_RESULTS \
    --local_cache=$local_cache \
    --repo=$REPO \
    --shamt=$SHAMT \
    --desired_targets=$DESIRED_TARGETS \
    --clean_local_cache=$CLEAN_LOCAL_CACHE \
    --key=duration --value=$duration

  python /send_build_stats.py --project_id=$(basename $PROJECT_ID) \
    --build_type=$BUILD_TYPE \
    --remote_accept_cached=$REMOTE_ACCEPT_CACHED \
    --cache_test_results=$CACHE_TEST_RESULTS \
    --local_cache=$local_cache \
    --repo=$REPO \
    --shamt=$SHAMT \
    --desired_targets=$DESIRED_TARGETS \
    --clean_local_cache=$CLEAN_LOCAL_CACHE \
    --key=critical --value=$critical

  python /send_build_stats.py --project_id=$(basename $PROJECT_ID) \
    --build_type=$BUILD_TYPE \
    --remote_accept_cached=$REMOTE_ACCEPT_CACHED \
    --cache_test_results=$CACHE_TEST_RESULTS \
    --local_cache=$local_cache \
    --repo=$REPO \
    --shamt=$SHAMT \
    --desired_targets=$DESIRED_TARGETS \
    --clean_local_cache=$CLEAN_LOCAL_CACHE \
    --key=actions --value=$actions

  python /send_build_stats.py --project_id=$(basename $PROJECT_ID) \
    --build_type=$BUILD_TYPE \
    --remote_accept_cached=$REMOTE_ACCEPT_CACHED \
    --cache_test_results=$CACHE_TEST_RESULTS \
    --local_cache=$local_cache \
    --repo=$REPO \
    --shamt=$SHAMT \
    --desired_targets=$DESIRED_TARGETS \
    --clean_local_cache=$CLEAN_LOCAL_CACHE \
    --key=build --value=1
done

