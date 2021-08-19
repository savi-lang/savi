##
# Dev stage: outputs an alpine image with everything needed for development.
# (this image is used by the `make ready` command to create a dev environment)

FROM alpine:3.14 as dev

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
RUN apk add --no-cache --update \
    sudo \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl lldb \
    cmake \
    libexecinfo-dev libretls-dev pcre2-dev \
    llvm11-dev llvm11-static \
    crystal shards

ENV CC=clang
ENV CXX=clang++

# Note that we require Pony and Crystal to be built with the same LLVM version,
# so we must use the version of LLVM that was used to build the crystal binary.
# This is just a sanity check to confirm that it was indeed built with the
# version that we expected when we installed our packages in the layer above.
RUN sh -c 'crystal --version | grep -C10 "LLVM: 11.1.0"'

# Build Crystal LLVM extension, which isn't distributed with the alpine package.
RUN sh -c 'clang++ -v -c \
  -o /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
  /usr/lib/crystal/core/llvm/ext/llvm_ext.cc `llvm-config --cxxflags`'

# Install Pony runtime bitcode.
# TODO: Use specific tag for `PONYC_VERSION` instead of `main` at next release.
# The commands we use below to build the bitcode currently only work on `main`.
# Specifically we need this commit to be present in the release we use:
# - https://github.com/ponylang/ponyc/commit/c043e9da809b4494783abb66365f5deea099e816
ENV PONYC_VERSION main
ENV PONYC_GIT_URL https://github.com/ponylang/ponyc
ENV CC=clang
ENV CXX=clang++
RUN git clone -b ${PONYC_VERSION} --depth 1 ${PONYC_GIT_URL} /tmp/ponyc && \
    cd /tmp/ponyc && \
    sed -i 's/SO_RCVTIMEO/SO_RCVTIMEO_OLD/g' src/libponyrt/lang/socket.c && \
    sed -i 's/SO_SNDTIMEO/SO_SNDTIMEO_OLD/g' src/libponyrt/lang/socket.c && \
    mkdir src/libponyrt/build && \
    cmake -S src/libponyrt -B src/libponyrt/build -DPONY_RUNTIME_BITCODE=true && \
    cmake --build src/libponyrt/build --target libponyrt_bc && \
    sudo cp src/libponyrt/build/libponyrt.bc /usr/lib/ && \
    rm -rf /tmp/ponyc

# Install Verona runtime (as shared library and static library).
# We hack the CMakeLists to avoid building the compiler/interpreter/stdlib.
RUN apk add --no-cache --update cmake ninja
ENV VERONA_VERSION 0332e6eb0bc23c334aefe6a2fba3ceb43be73e1c
# TODO: Use upstream, official verona repository.
ENV VERONA_GIT_URL https://github.com/jemc/verona
RUN git init /tmp/verona && \
    cd /tmp/verona && \
    git remote add origin ${VERONA_GIT_URL} && \
    git fetch --depth 1 origin ${VERONA_VERSION} && \
    git checkout FETCH_HEAD && \
    git submodule update --init --recursive
# TODO: Combine the two RUN commands into one, after all is working.
RUN cd /tmp/verona && \
    mkdir ninja_build && \
    cd ninja_build && \
    sed -i 's/add_subdirectory.compiler.//g' ../src/CMakeLists.txt && \
    sed -i 's/add_subdirectory.interpreter.//g' ../src/CMakeLists.txt && \
    sed -i 's/add_subdirectory.stdlib.//g' ../src/CMakeLists.txt && \
    cat ../src/CMakeLists.txt && \
    cmake .. -GNinja -DCMAKE_BUILD_TYPE=Debug && \
    ninja install && \
    sudo cp dist/lib/libverona.so           /usr/lib/ && \
    sudo cp dist/lib/libverona-sys.so       /usr/lib/ && \
    sudo cp dist/lib/libverona-static.a     /usr/lib/ && \
    sudo cp dist/lib/libverona-sys-static.a /usr/lib/ && \
    rm -rf /tmp/verona

# TODO: Use multi-stage build here to carry over only the files we need.

# Create a basic working directory to use for code.
RUN mkdir /opt/code
WORKDIR /opt/code

##
# Build stage: outputs an alpine image that contains a working Savi compiler
# (this image is used only as a precursor to the release stage)

FROM alpine:3.14 as build

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
# This line is kept intentionally the same as it was for the dev stage,
# so that it can share the same docker image layer cache entry.
RUN apk add --no-cache --update \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl \
    libexecinfo-dev libretls-dev pcre2-dev \
    llvm11-dev llvm11-static \
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
RUN make /tmp/bin/savi

##
# Release stage: outputs a minimal alpine image with a working Savi compiler
# (this image is made available on DockerHub for download)

FROM alpine:3.14 as release

# Install runtime dependencies of the compiler.
RUN apk add --no-cache --update \
  llvm11-libs gc pcre gcc clang lld libgcc libevent musl-dev libexecinfo-dev

RUN mkdir /opt/code
WORKDIR /opt/code

COPY --from=dev /usr/lib/libponyrt.bc \
                /usr/lib/

COPY packages    /opt/savi/packages
COPY --from=build /tmp/bin/savi /bin/savi

ENTRYPOINT ["/bin/savi"]
