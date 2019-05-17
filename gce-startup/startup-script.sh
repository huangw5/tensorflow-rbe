#!/bin/bash
#
# This script is used to bootstrap the docker container on GCE VMs.

function get_metadata() {
  # Do not exit on curl error.
  set +e
  key="$1"
  curl -fsS "http://metadata.google.internal/computeMetadata/v1/instance/$key" -H "Metadata-Flavor:Google"
  set -e
}

set -x

SCRIPT=$(get_metadata "attributes/script")
if [ -z "$SCRIPT" ]; then
        SCRIPT="/build.sh"
fi

cat /dev-foundry.json | docker login -u _json_key --password-stdin https://gcr.io
cp /dev-foundry.json /tmp/dev-foundry.json
docker run --rm -it -v /tmp:/tmp \
        -e GOOGLE_APPLICATION_CREDENTIALS=/tmp/dev-foundry.json \
        gcr.io/cst-c-test-0/tf-builder:demo "$SCRIPT"

# Delete the VM itself when it is done.
ZONE=$(get_metadata "zone")
gcloud compute instances delete "$(hostname)" --zone="$(basename "$ZONE")" --quiet
