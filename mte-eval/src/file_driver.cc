#include <cstdint>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include <vector>

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size);

int main(int argc, char **argv) {
  if (argc != 2) {
    std::cerr << "usage: " << argv[0] << " <input-file>\n";
    return 2;
  }

  const std::string path = argv[1];
  std::ifstream input(path, std::ios::binary);
  if (!input) {
    std::cerr << "failed to open: " << path << "\n";
    return 2;
  }

  std::vector<uint8_t> data((std::istreambuf_iterator<char>(input)),
                            std::istreambuf_iterator<char>());
  return LLVMFuzzerTestOneInput(data.data(), data.size());
}
