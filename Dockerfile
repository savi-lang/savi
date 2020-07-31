##
# Dev stage: outputs an alpine image with everything needed for development.
# (this image is used by the `make ready` command to create a dev environment)

FROM alpine:3.12 as dev

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
RUN apk add --no-cache --update \
    sudo \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl lldb \
    cmake \
    libexecinfo-dev libressl-dev pcre2-dev \
    llvm10-dev llvm10-static \
    crystal shards

ENV CC=clang
ENV CXX=clang++

# Note that we require Pony and Crystal to be built with the same LLVM version,
# so we must use the version of LLVM that was used to build the crystal binary.
# This is just a sanity check to confirm that it was indeed built with the
# version that we expected when we installed our packages in the layer above.
RUN sh -c 'crystal --version | grep -C10 "LLVM: 10.0.0"'

# Build Crystal LLVM extension, which isn't distributed with the alpine package.
RUN sh -c 'clang++ -v -c \
  -o /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
  /usr/lib/crystal/core/llvm/ext/llvm_ext.cc `llvm-config --cxxflags`'

# Add pony patches
RUN mkdir /tmp/patches
COPY ponypatches/* /tmp/patches/

# Install Pony runtime (as shared library, static library, and bitcode).
ENV PONYC_VERSION 0.35.1
ENV PONYC_GIT_URL https://github.com/ponylang/ponyc
RUN git clone -b ${PONYC_VERSION} --depth 1 ${PONYC_GIT_URL} /tmp/ponyc && \
    cd /tmp/ponyc && \
    sed -i 's/void Main_/\/\/ void Main_/g' src/libponyrt/sched/start.c && \
    sed -i 's/  Main_/  \/\/ Main_/g' src/libponyrt/sched/start.c && \
    mkdir .mare_patches && \
    git apply /tmp/patches/* && \
    make runtime-bitcode=yes verbose=yes config=debug cross-libponyrt && \
    clang -shared -fpic -pthread -ldl -latomic -lexecinfo -o libponyrt.so build/native/build_debug/src/libponyrt/libponyrt.bc && \
    sudo mv libponyrt.so /usr/lib/ && \
    sudo cp build/native/build_debug/src/libponyrt/libponyrt.bc /usr/lib/ && \
    sudo cp build/native/build_debug/src/libponyrt/libponyrt.a /usr/lib/ && \
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
# Build stage: outputs an alpine image that contains a working Mare compiler
# (this image is used only as a precursor to the release stage)

FROM alpine:3.12 as build

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
# This line is kept intentionally the same as it was for the dev stage,
# so that it can share the same docker image layer cache entry.
RUN apk add --no-cache --update \
    alpine-sdk coreutils linux-headers clang-dev lld \
    valgrind perl \
    libexecinfo-dev libressl-dev pcre2-dev \
    llvm10-dev llvm10-static \
    crystal shards

# TODO: Don't bother with every possible libponyrt distribution format.
COPY --from=dev /usr/lib/libponyrt.* \
                /usr/lib/
COPY --from=dev /usr/lib/crystal/core/llvm/ext/llvm_ext.o \
                /usr/lib/crystal/core/llvm/ext/

RUN mkdir /opt/mare
WORKDIR /opt/mare
COPY Makefile main.cr /opt/mare/
COPY lib /opt/mare/lib
COPY src /opt/mare/src
RUN make /tmp/bin/mare

##
# Release stage: outputs a minimal alpine image with a working Mare compiler
# (this image is made available on DockerHub for download)

FROM alpine:3.12 as release

# Install runtime dependencies of the compiler.
RUN apk add --no-cache --update \
  llvm10-libs gc pcre gcc clang lld libgcc libevent musl-dev libexecinfo-dev

RUN mkdir /opt/code
WORKDIR /opt/code

# TODO: Don't bother with every possible libponyrt distribution format.
COPY --from=dev /usr/lib/libponyrt.so \
                /usr/lib/
COPY --from=dev /usr/lib/libponyrt.a \
                /usr/lib/libponyrt.bc \
                /usr/lib/

COPY src/prelude /opt/mare/src/prelude
COPY packages    /opt/mare/packages
COPY --from=build /tmp/bin/mare /bin/mare

ENTRYPOINT ["/bin/mare"]
