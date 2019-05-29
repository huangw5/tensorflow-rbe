We demonstrate how to run [bazel-stress](https://github.com/werkt/bazel-stress)
benchmark against Google Remote Build Execution.

# Build docker container

```
git clone https://github.com/huangw5/tensorflow-rbe.git
cd tensorflow-rbe/docker
docker build --tag "bazel-rbe" .
```

# Run single bazel-stress builder

First start the container in interactive mode:

```
docker run --rm -it \
  -e GOOGLE_APPLICATION_CREDENTIALS=/path/to/rbe_credentials.json \
  -v /path/to/rbe_credentials.json:/path/to/rbe_credentials.json \
  bazel-rbe:latest bash
```

Then inside the container (replace `your_rbe_project` and
`your_rbe_instance_name` with your own):

```
# Checkout bazel-stress
git clone https://github.com/werkt/bazel-stress.git
cd bazel-stress

# Setup the WORKSPACE
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

build:remote --remote_instance_name=projects/your_rbe_project/instances/your_rbe_instance_name
build:remote --remote_accept_cached=false
EOF

# Generate targets (here we use 7 shamt and 100000 desired targets)
bazel run tools:gen 7 100000 > BUILD

# Kick off the build remotely.
bazel build --config=remote :all
```

# Run many bazel-stress builders in parallel

We provide a convenient script
[build-stress.sh](https://github.com/huangw5/tensorflow-rbe/blob/master/docker/build-stress.sh)
in the docker container to run many bazel-stress in parallel. We use Google
Cloud Compute Engine as an example of how to run 50 bazel-stress builders in
parallel.

## Prerequisites

1.  You need to have Google Compute Engine API enabled
2.  You need to grant necessary permissions to the GCE service account so that
    it can run your builds against Google Remote Build Execution and pull the
    docker image from either DockerHub or Google Container Registry

For (1), you can enable GCE API followed this
[document](https://cloud.google.com/apis/docs/enable-disable-apis).

For (2), you can follow the
[official documentation](https://cloud.google.com/remote-build-execution/docs/access-control)
of Google Remote Build Execution. Note that you will need to be whitelisted in
order to access the documentation. See
[the instructions](https://groups.google.com/forum/#!forum/rbe-alpha-customers).

## Run bazel-stress builders in Managed Instance Group (MIG)

### Step 1: Create an instance template

1.  Visit https://console.cloud.google.com/compute/instanceTemplates/add Make
    sure you are using the correct cloud project.
2.  Put a name in "Name" section, e.g. `bazel-stress-builders-200-jobs`.
3.  Change the "Machine type" to `n1-highcpu-8`.
4.  Check "Deploy a container image to this VM instance"
5.  Put the name of your container built from
    [Dockerfile](https://github.com/huangw5/tensorflow-rbe/blob/master/docker/Dockerfile),
    e.g. `gcr.io/cst-c-test-0/tf-builder:demo`.
6.  Put "Command" as `/build-stress.sh`. This is
    [the script](https://github.com/huangw5/tensorflow-rbe/blob/master/docker/build-stress.sh)
    included in this repo.
7.  Fill out the following "Environment variables":
    *   `PROJECT_ID` is the project that has Remote Build Execution API enabled,
        e.g. `projects/rbe-prod-demo`
    *   `INSTANCE_NAME` is the RBE instance, e.g. `instances/default_instance`
    *   `NUM_OF_RUNS` controls how many build you want to run, e.g. `1000`
    *   `NUM_OF_JOBS` controls the parallelism of bazel. This is passed to
        [`--jobs`](https://docs.bazel.build/versions/master/command-line-reference.html#flag--jobs)
        flag of bazel, e.g. 200.
8.  Grant the cloud-platform scope to the VM by selecting "Allow full access to
    all Cloud APIs".
9.  Click "Create".

The page looks like the following:

![Image of template](https://github.com/huangw5/tensorflow-rbe/raw/update-readme/bazel-template.png)

### Step 2: Create a Managed Instance Group

1.  Click the template you created above:
    https://console.cloud.google.com/compute/instanceTemplates/details/bazel-stress-builders-200-jobs.
2.  Click "CREATE INSTANCE GROUP" on the top.
3.  Put a name for the MIG in "Name" section, e.g. `bazel-stress-builders`.
4.  Select a "Zone" in `us-central1`, e.g. `us-entral1-a`.
5.  Set "Autoscaling" to `off`.
6.  Set "Number of instances" to the number of builders you desire, e.g. 50.
7.  Click "Create".

The page looks like the following:

![Image of template](https://github.com/huangw5/tensorflow-rbe/raw/update-readme/bazel-mig.png)

Wait for a few minutes, and you should be able to see 50 VMs are up and start
sending builds to Google Remote Build Execution. The `build-stress.sh` script
also sends the build durations via a custom metric
`custom.googleapis.com/tf_build/duration`. You can view it using
[Stackdriver Metrics Explorer](https://app.google.stackdriver.com/metrics-explorer).
