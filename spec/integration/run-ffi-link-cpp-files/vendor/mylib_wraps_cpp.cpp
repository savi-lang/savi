#include <stdexcept>

static void throw_if_low(int value) {
  if (value < 10)
    throw std::runtime_error("whoops");
}

extern "C" {

int mylib_wraps_cpp(int value)
{
  try {
    throw_if_low(value);
    return value;
  } catch (std::runtime_error err) {
    return 0;
  }
}

}
