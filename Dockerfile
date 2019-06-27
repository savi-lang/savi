##
# Dev stage: outputs an alpine image with everything needed for development.
# (this image is used by the `make ready` command to create a dev environment)

FROM alpine:3.9 as dev

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
RUN apk add --no-cache --update \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl \
    libexecinfo-dev libressl-dev pcre2-dev \
    llvm5-dev llvm5-static \
    crystal shards

ENV CC=clang
ENV CXX=clang++

# Note that we require Pony and Crystal to be built with the same LLVM version,
# so we must use the version of LLVM that was used to build the crystal binary.
# This is just a sanity check to confirm that it was indeed built with the
# version that we expected when we installed our packages in the layer above.
RUN sh -c 'crystal --version | grep -C10 "LLVM: 5.0.1"'

# Build Crystal LLVM extension, which isn't distributed with the alpine package.
RUN sh -c 'clang++ -v -c \
  -o /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
  /usr/lib/crystal/core/llvm/ext/llvm_ext.cc `llvm-config --cxxflags`'

# Install Pony runtime (as shared library, static library, and bitcode).
# TODO: Remove MinSizeRel find-and-replace hacks when ponyc is fixed.
ENV PONYC_VERSION 0.26.0
ENV PONYC_GIT_URL https://github.com/ponylang/ponyc
RUN git clone -b ${PONYC_VERSION} --depth 1 ${PONYC_GIT_URL} /tmp/ponyc && \
    cd /tmp/ponyc && \
    sed -i 's/RelWithDebInfo/MinSizeRel/g' Makefile && \
    sed -i 's/RelWithDebInfo/MinSizeRel/g' src/common/llvm_config_begin.h && \
    make default_pic=true runtime-bitcode=yes verbose=yes libponyrt && \
    clang -shared -fpic -pthread -ldl -latomic -lexecinfo -o libponyrt.so build/release/lib/native/libponyrt.bc && \
    sudo mv libponyrt.so /usr/lib/ && \
    sudo cp build/release/lib/native/libponyrt.bc /usr/local/lib/ && \
    sudo cp build/release/lib/native/libponyrt.a /usr/local/lib/ && \
    rm -rf /tmp/ponyc

# TODO: Use multi-stage build here to carry over only the files we need.

# Create a basic working directory to use for code.
RUN mkdir /opt/code
WORKDIR /opt/code

##
# Build stage: outputs an alpine image that contains a working Mare compiler
# (this image is used only as a precursor to the release stage)

FROM alpine:3.9 as build

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
# This line is kept intentionally the same as it was for the dev stage,
# so that it can share the same docker image layer cache entry.
RUN apk add --no-cache --update \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl \
    libexecinfo-dev libressl-dev pcre2-dev \
    llvm5-dev llvm5-static \
    crystal shards

# TODO: Don't bother with every possible libponyrt distribution format.
COPY --from=dev /usr/lib/libponyrt.so \
                /usr/lib/
COPY --from=dev /usr/local/lib/libponyrt.a \
                /usr/local/lib/libponyrt.bc \
                /usr/local/lib/
COPY --from=dev /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
                /usr/lib/crystal/core/llvm/ext/

RUN mkdir /opt/mare
WORKDIR /opt/mare
COPY . /opt/mare
RUN shards install && make /tmp/bin/mare

##
# Release stage: outputs a minimal alpine image with a working Mare compiler
# (this image is made available on DockerHub for download)

FROM alpine:3.9 as release

# Install runtime dependencies of the compiler.
RUN apk add --no-cache --update \
  llvm5-libs gc pcre gcc clang lld libgcc libevent musl-dev libexecinfo-dev

RUN mkdir /opt/code
WORKDIR /opt/code

# TODO: Don't bother with every possible libponyrt distribution format.
COPY --from=dev /usr/lib/libponyrt.so \
                /usr/lib/
COPY --from=dev /usr/local/lib/libponyrt.a \
                /usr/local/lib/libponyrt.bc \
                /usr/local/lib/

COPY src/prelude /opt/mare/src/prelude
COPY --from=build /tmp/bin/mare /bin/mare

ENTRYPOINT /bin/mare
