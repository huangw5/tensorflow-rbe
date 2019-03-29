This repo contains the Bazel configurations for building TensorFlow CPU/GPU.

# Build docker container

```
cd docker
docker build  --tag "tf-rbe" .
```

# Kick off TensorFlow CPU (py2) builds/tests

```
docker run --rm -it -e BUILD_TYPE=cpu tf-rbe:latest /build.sh
```

# Kick off TensorFlow GPU (py2) builds/tests

```
docker run --rm -it -e BUILD_TYPE=cpu \
  -e PROJECT_ID=projects/your_rbe_project_id \
  -e INSTANCE_NAME=instances/your_rbe_instance_name \
  -e GOOGLE_APPLICATION_CREDENTIALS=/path/to/rbe_credentials.json \
  tf-rbe:latest /build.sh
```

See all other variables in `build.sh`.
