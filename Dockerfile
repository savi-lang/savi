##
# Dev stage: outputs an alpine image with everything needed for development.
# (this image is used by the `make ready` command to create a dev environment)

# TODO: Don't use alpine:edge - use alpine:3.15 when it's available
FROM alpine:edge as dev

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
RUN apk add --no-cache --update \
    sudo \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl lldb \
    cmake \
    libexecinfo-dev libretls-dev pcre2-dev \
    llvm12-dev llvm12-static \
    crystal shards

ENV CC=clang
ENV CXX=clang++

# Build Crystal LLVM extension, which isn't distributed with the alpine package.
RUN sh -c 'clang++ -v -c \
  -o /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
  /usr/lib/crystal/core/llvm/ext/llvm_ext.cc `llvm-config --cxxflags`'

# Install runtime bitcode.
ENV RUNTIME_RELEASE_URL https://github.com/savi-lang/runtime-bitcode/releases/download/20211101
RUN wget "${RUNTIME_RELEASE_URL}/x86_64-unknown-linux-musl-libponyrt.bc" \
      -O /tmp/libsavi_runtime.bc && \
    sudo mv /tmp/libsavi_runtime.bc /usr/lib/

# Create a basic working directory to use for code.
RUN mkdir /opt/code
WORKDIR /opt/code

##
# Build stage: outputs an alpine image that contains a working Savi compiler
# (this image is used only as a precursor to the release stage)

# TODO: Don't use alpine:edge - use alpine:3.15 when it's available
FROM alpine:edge as build

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
# This line is kept intentionally the same as it was for the dev stage,
# so that it can share the same docker image layer cache entry.
RUN apk add --no-cache --update \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl \
    libexecinfo-dev libretls-dev pcre2-dev \
    llvm12-dev llvm12-static \
    crystal shards

COPY --from=dev /usr/lib/libponyrt.bc \
                /usr/lib/
COPY --from=dev /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
                /usr/lib/crystal/core/llvm/ext/

RUN mkdir /opt/savi
WORKDIR /opt/savi
COPY Makefile main.cr /opt/savi/
COPY lib /opt/savi/lib
COPY src /opt/savi/src
RUN make bin/savi

##
# Release stage: outputs a minimal alpine image with a working Savi compiler
# (this image is made available on DockerHub for download)

# TODO: Don't use alpine:edge - use alpine:3.15 when it's available
FROM alpine:edge as release

# Install runtime dependencies of the compiler.
RUN apk add --no-cache --update \
  llvm11-libs gc pcre gcc clang lld libgcc libevent musl-dev libexecinfo-dev

RUN mkdir /opt/code
WORKDIR /opt/code

COPY --from=dev /usr/lib/libponyrt.bc \
                /usr/lib/

COPY packages    /opt/savi/packages
COPY --from=build bin/savi /bin/savi

ENTRYPOINT ["/bin/savi"]
