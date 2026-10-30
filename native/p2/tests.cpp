#include "value.hpp"
#include "cas.hpp"
#include <iostream>
using namespace catalyst;
int main() {
  int checks = 0;
  auto check = [&](bool passed) { require(passed, "Native unit assertion"); ++checks; };
  auto rejects = [&](auto action) { bool failed = false; try { action(); } catch (const std::exception&) { failed = true; } check(failed); };
  check(sha256("abc") == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad");
  for (auto text : {"n", "t", "f", "i-9223372036854775808;", "i18446744073709551615;", "a3:i1;s1:xf", "d1:s1:aa0:"})
    check(encode(decode(text)) == text);
  for (auto text : {"", "i01;", "i-0;", "i18446744073709551616;", "i-9223372036854775809;", "s1:\n", "a1:", "d2:s1:ans1:at", "d2:s1:bns1:an", "nt", "z0:"})
    rejects([&] { decode(text); });
  check(floorDiv(Integer(-300), Integer(1000)) == -1);
  check(floorDiv(Integer(-1000), Integer(1000)) == -1);
  check(floorDiv(Integer(1300), Integer(1000)) == 1);
  rejects([&] { i64(MAX64 + 1); }); rejects([&] { i64(MIN64 - 1); });
  rejects([&] { u32(MAX32 + 1); }); rejects([&] { nonnegative(-1); });
  check(sample("0123456789abcdeffedcba9876543210", Integer("18364758544493064720"), 0x13579bdf, 0x2468ace0) == 697764476);
  check(sample(std::string(32, '0'), Integer(0), 0, 0) == 0x6627e8d5);
  check(sample(std::string(32, 'f'), Integer(0), 0xffffffff, 0xffffffff) == 0x408f276d);
  char pattern[]="/private/tmp/catalyst-cas-unit-XXXXXX";
  auto directory=mkdtemp(pattern);require(directory,"Native test directory");
  try {
    CasStore store(directory);
    Value array=Value::list(),map=Value::dict(),rows=Value::dict(),index=Value::dict();
    for(int i=0;i<80;++i){array.array.emplace_back(std::string(4096,'a'+i%26));map.map[std::to_string(i)]=array.array.back();}
    for(const auto& value:{array,map,Value::list({array}),Value::dict({{"nested",map}})}){
      auto root=store.value(value);
      check(encode(store.readValue(root))==encode(value));
      check(store.value(value)==root);
    }
    for(int i=0;i<256;++i){std::ostringstream id;id<<std::hex<<std::setw(30)<<std::setfill('0')<<i<<"00";rows.map[id.str()]=std::string(256,'x');index.map[id.str().substr(28,2)]=sha256(id.str());}
    for(bool projection:{false,true}){auto root=store.rows(rows,"00",projection);check(store.get(root).at("kind").text()==(projection?"projectionBranch":"entitiesBranch"));check(encode(store.readRows(root))==encode(rows));}
    auto root=store.index(index);check(store.get(root).at("kind").text()=="indexBranch");check(encode(store.readIndex(root))==encode(index));
    for(const auto& entry:std::filesystem::directory_iterator(directory))check(entry.file_size()<=PAGE_BYTES);
    rejects([&]{store.get(std::string(64,'0'));});
    auto valid=store.value(Value("integrity"));std::ofstream(std::string(directory)+"/"+valid+".canon")<<"n";
    rejects([&]{store.get(valid);});
  } catch(...) {std::filesystem::remove_all(directory);throw;}
  std::filesystem::remove_all(directory);
  std::cout << "{\"passed\":true,\"checks\":" << checks << "}\n";
}
