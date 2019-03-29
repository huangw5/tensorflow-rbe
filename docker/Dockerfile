FROM ubuntu:18.04

ARG BAZEL_VERSION=0.23.2

# This is needed to avoid user interaction when installing expect.
ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update
RUN apt-get install -y --no-install-recommends \
      patch \
      wget \
      unzip \
      uuid \
      python \
      python-pip \
      python-setuptools \
      python3 \
      python3-pip \
      python3-setuptools \
      openjdk-8-jdk-headless \
      git \
      curl \
      vim \
      expect \
      tcl8.6

RUN wget -q https://github.com/bazelbuild/bazel/releases/download/$BAZEL_VERSION/bazel-$BAZEL_VERSION-linux-x86_64 \
  && mv bazel-$BAZEL_VERSION-linux-x86_64 /usr/bin/bazel \
  && chmod +x /usr/bin/bazel

RUN pip install keras_applications==1.0.4 --no-deps && \
    pip install keras_preprocessing==1.0.2 --no-deps && \
    pip install h5py==2.8.0 && \
    pip install wheel && \
    pip install grpcio && \
    pip install tensorflow_estimator && \
    pip install portpicker && \
    pip install scipy && \
    pip3 install keras_applications==1.0.4 --no-deps && \
    pip3 install keras_preprocessing==1.0.2 --no-deps && \
    pip3 install h5py==2.8.0 && \
    pip3 install wheel && \
    pip3 install grpcio && \
    pip3 install tensorflow_estimator && \
    pip3 install portpicker && \
    pip3 install scipy

# To pass check in configure.py that python exists in the PYTHON_BIN_PATH
RUN mkdir -p /opt/python3.6/bin/ && ln -s /usr/bin/python3 /opt/python3.6/bin/python3

COPY .bazelrc.rbe.gpu /.bazelrc.rbe.gpu
COPY .bazelrc.rbe.cpu /.bazelrc.rbe.cpu
COPY build.sh /build.sh
RUN chmod +x /build.sh
WORKDIR /tf
