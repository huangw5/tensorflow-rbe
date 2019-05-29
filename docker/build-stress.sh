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

[ -z "$NUM_OF_RUNS" ] && NUM_OF_RUNS=$(get_metadata "attributes/num_of_runs")
[ -z "$NUM_OF_RUNS" ] && NUM_OF_RUNS=1

[ -z "$NUM_OF_JOBS" ] && NUM_OF_JOBS=$(get_metadata "attributes/num_of_jobs")
[ -z "$NUM_OF_JOBS" ] && NUM_OF_JOBS=500

[ -z "$SHAMT" ] && SHAMT=$(get_metadata "attributes/shamt")
[ -z "$SHAMT" ] && SHAMT=7

[ -z "$DESIRED_TARGETS" ] && DESIRED_TARGETS=$(get_metadata "attributes/desired_targets")
[ -z "$DESIRED_TARGETS" ] && DESIRED_TARGETS=100000

if [ -n "$GOOGLE_APPLICATION_CREDENTIALS" ]; then
  AUTH_CREDENTIALS=" --auth_credentials=$GOOGLE_APPLICATION_CREDENTIALS "
fi

REPO=https://github.com/werkt/bazel-stress.git

BUILD_LOG=/tmp/build.log

function log_message() {
  echo "[$(date)] $@"
}

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
EOF

# Configure bazelrc.
curl -LO https://raw.githubusercontent.com/bazelbuild/bazel-toolchains/master/bazelrc/bazel-0.25.0.bazelrc
cat <<"EOF" >> .bazelrc
import %workspace%/bazel-0.25.0.bazelrc

build:remote --remote_instance_name=projects/rbe-prod-demo/instances/default_instance
build:remote --remote_accept_cached=false
EOF


# Generate BUILD file.
bazel run tools:gen -- $SHAMT $DESIRED_TARGETS > BUILD

for ((i=0;i<$NUM_OF_RUNS;i++))
do
  log_message "Running bazel clean"
  bazel clean
  log_message "Start building (run $((i+1)) / $NUM_OF_RUNS)"
  unbuffer bazel build \
    --keep_going \
    --config=remote \
    --loading_phase_threads=HOST_CPUS \
    --jobs="$NUM_OF_JOBS" ${AUTH_CREDENTIALS} \
    --remote_instance_name="$PROJECT_ID/$INSTANCE_NAME" \
    :all | tee "$BUILD_LOG"
  log_message "Finished (run $((i+1)) / $NUM_OF_RUNS)"

  # Extract the build stats.
  if cat "$BUILD_LOG" | grep 'Build did NOT complete successfully' > /dev/null; then
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
  log_message "duration: $duration, actions: $actions, success: $success, critical: $critical, repo: $REPO"
  # Send the duration to GCP custom metric.
  python /send_build_stats.py --project_id=$(basename $PROJECT_ID) \
    --repo=$REPO \
    --shamt=$SHAMT \
    --desired_targets=$DESIRED_TARGETS \
    --success=$success \
    --key=duration --value=$duration
done
