# TODO: Stabilize on alpine 3.9 when it is released.
FROM alpine:edge as dev

# Install build tools, Pony dependencies, LLVM libraries, and Crystal.
# TODO: Fix indentation style here for consistency.
RUN apk add --no-cache --update \
    alpine-sdk coreutils linux-headers clang-dev binutils-gold \
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
