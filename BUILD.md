# Building savi from source

## FreeBSD

You need to build Pony first (please also consult Pony's documentation):

```sh
sudo pkg install -y cmake gmake libunwind git

git clone https://github.com/ponylang/ponyc
cd ponyc
export CC=clang10
export CXX=clang++10
export CMAKE_C_FLAGS=-I/usr/local/include
export CMAKE_CXX_FLAGS=-I/usr/local/include
gmake libs
gmake configure lto=yes runtime-bitcode=yes
gmake build
sudo cp build/release/libponyrt.bc /usr/local/lib
```

We only need file `libponyrt.bc`. Either copy it to a system library location,
or set `SAVI_PONYRT_BC_PATH` to the directory where it can be found.

Then build `savi`:

```sh
crystal build main.cr
# sudo cp ./main /usr/local/bin/savi
```
