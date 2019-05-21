This repo contains the Bazel configurations for building TensorFlow CPU/GPU.

# Build docker container

```
cd docker
docker build  --tag "tf-rbe" .
```

# Kick off TensorFlow CPU (py2) builds/tests

```
docker run --rm -it -e BUILD_TYPE=cpu \
  -e PROJECT_ID=projects/your_rbe_project_id \
  -e INSTANCE_NAME=instances/your_rbe_instance_name \
  -e GOOGLE_APPLICATION_CREDENTIALS=/path/to/rbe_credentials.json \
  -v /path/to/rbe_credentials.json:/path/to/rbe_credentials.json \
  tf-rbe:latest /build.sh
```

# Kick off TensorFlow GPU (py3) builds/tests

```
docker run --rm -it -e BUILD_TYPE=gpu \
  -e PROJECT_ID=projects/your_rbe_project_id \
  -e INSTANCE_NAME=instances/your_rbe_instance_name \
  -e GOOGLE_APPLICATION_CREDENTIALS=/path/to/rbe_credentials.json \
  -v /path/to/rbe_credentials.json:/path/to/rbe_credentials.json \
  tf-rbe:latest /build.sh
```

See all other variables in `build.sh`.

# Build TensorFlow manually inside docker container

First start the container in interactive mode:

```
docker run --rm -it \
  -e GOOGLE_APPLICATION_CREDENTIALS=/path/to/rbe_credentials.json \
  -v /path/to/rbe_credentials.json:/path/to/rbe_credentials.json \
  tf-rbe:latest bash
```

Then inside the container:

```
# Checkout TensorFlow.
git clone https://github.com/tensorflow/tensorflow.git
cd tensorflow

# Run configure (For CPU builds only)
export TF_NEED_GCP=0
export TF_NEED_HDFS=0
export TF_NEED_CUDA=0
# PYTHON_BIN_PATH must be set to path of python in exec container
export PYTHON_BIN_PATH="/usr/bin/python"
yes "" | ./configure

# Call bazel with the provided
[bazelrc](https://github.com/huangw5/tensorflow-rbe/blob/master/docker/.bazelrc.rbe.cpu).

bazel --bazelrc=/.bazelrc.rbe.cpu test --config=remote \
  --remote_instance_name=projects/your_rbe_project/instances/your_rbe_istance \
  -- //tensorflow/... -//tensorflow/lite/... -//tensorflow/contrib/...
```
