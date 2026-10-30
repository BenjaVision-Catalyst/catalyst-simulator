#pragma once
#include "value.hpp"
#include <filesystem>
#include <fcntl.h>
#include <unistd.h>

namespace catalyst {
inline constexpr size_t PAGE_BYTES=16384;
inline bool hashId(const std::string& value){return value.size()==64&&value.find_first_not_of("0123456789abcdef")==std::string::npos;}
class CasStore {
 std::string directory;
public:
 explicit CasStore(std::string path):directory(std::move(path)){std::filesystem::create_directories(directory);}
 Value get(const std::string& hash)const{require(hashId(hash),"Artifact hash");auto raw=readFile(directory+"/"+hash+".canon");require(raw.size()<=PAGE_BYTES&&sha256(raw)==hash,"Artifact integrity");return decode(raw);}
 std::string put(const Value& node){
  auto raw=encode(node);require(raw.size()<=PAGE_BYTES,"Artifact page size");auto hash=sha256(raw),path=directory+"/"+hash+".canon";
  if(std::filesystem::exists(path)){require(readFile(path)==raw,"Artifact collision");return hash;}
  auto temporary=path+"."+std::to_string(getpid())+".tmp";int file=open(temporary.c_str(),O_WRONLY|O_CREAT|O_TRUNC,0600);require(file>=0,"Artifact create");
  size_t offset=0;while(offset<raw.size()){auto count=write(file,raw.data()+offset,raw.size()-offset);if(count<=0){close(file);throw std::runtime_error("Artifact write");}offset+=size_t(count);}
  require(fsync(file)==0,"Artifact fsync");close(file);require(rename(temporary.c_str(),path.c_str())==0,"Artifact publish");
  int folder=open(directory.c_str(),O_RDONLY);require(folder>=0&&fsync(folder)==0,"Artifact directory fsync");close(folder);return hash;
 }
 std::string value(const Value& value){
  Value leaf=Value::dict({{"kind","value"},{"value",value}});bool fits=false;
  try{fits=encode(leaf).size()<=PAGE_BYTES;}catch(const std::runtime_error&){if(value.kind!=Value::Map&&value.kind!=Value::Array)throw;}
  if(fits)return put(leaf);
  if(value.kind==Value::Array){
   require(!value.array.empty(),"Artifact array");
   if(value.array.size()==1)return put(Value::dict({{"kind","item"},{"value",this->value(value.at(0))}}));
   auto middle=value.array.begin()+value.array.size()/2;
   return put(Value::dict({{"kind","array"},{"left",this->value(Value::list({value.array.begin(),middle}))},{"right",this->value(Value::list({middle,value.array.end()}))}}));
  }
  require(value.kind==Value::Map&&!value.map.empty(),"Artifact value");
  if(value.map.size()==1)return put(Value::dict({{"kind","entry"},{"key",value.map.begin()->first},{"value",this->value(value.map.begin()->second)}}));
  auto middle=value.map.begin();std::advance(middle,value.map.size()/2);
  return put(Value::dict({{"kind","map"},{"left",this->value(Value::dict({value.map.begin(),middle}))},{"right",this->value(Value::dict({middle,value.map.end()}))}}));
 }
 Value readValue(const std::string& hash)const{
  auto node=get(hash);auto kind=node.at("kind").text();
  if(kind=="value")return node.at("value");
  if(kind=="item")return Value::list({readValue(node.at("value").text())});
  if(kind=="entry")return Value::dict({{node.at("key").text(),readValue(node.at("value").text())}});
  require(kind=="array"||kind=="map","Artifact value kind");auto left=readValue(node.at("left").text()),right=readValue(node.at("right").text());
  if(kind=="array"){require(left.kind==Value::Array&&right.kind==Value::Array,"Artifact array kind");left.array.insert(left.array.end(),right.array.begin(),right.array.end());}
  else{require(left.kind==Value::Map&&right.kind==Value::Map,"Artifact map kind");for(auto& kv:right.map)require(left.map.emplace(kv).second,"Artifact duplicate key");}return left;
 }
 std::string index(const Value& entries){
  Value leaf=Value::dict({{"kind","index"},{"entries",entries}});if(encode(leaf).size()<=PAGE_BYTES)return put(leaf);
  auto middle=entries.map.begin();std::advance(middle,entries.map.size()/2);
  return put(Value::dict({{"kind","indexBranch"},{"left",index(Value::dict({entries.map.begin(),middle}))},{"right",index(Value::dict({middle,entries.map.end()}))}}));
 }
 Value readIndex(const std::string& hash)const{
  auto node=get(hash);if(node.at("kind").text()=="index")return node.at("entries");
  require(node.at("kind").text()=="indexBranch","Artifact index kind");auto left=readIndex(node.at("left").text()),right=readIndex(node.at("right").text());
  for(auto& kv:right.map)require(left.map.emplace(kv).second,"Artifact duplicate bucket");return left;
 }
 std::string rows(const Value& rows,const std::string& suffix,bool projection){
  std::string kind=projection?"projection":"entities";Value leaf=Value::dict({{"kind",kind},{"suffix",suffix},{"rows",rows}});
  if(rows.map.size()<=128&&encode(leaf).size()<=PAGE_BYTES)return put(leaf);
  require(suffix.size()<32,"Artifact row too large");Value children=Value::dict();
  for(char digit:std::string("0123456789abcdef")){auto tail=std::string(1,digit)+suffix;Value selected=Value::dict();for(auto& kv:rows.map)if(kv.first.size()>=tail.size()&&kv.first.compare(kv.first.size()-tail.size(),tail.size(),tail)==0)selected.map.emplace(kv);
   if(!selected.map.empty())children.map[std::string(1,digit)]=this->rows(selected,tail,projection);}
  return put(Value::dict({{"kind",kind+"Branch"},{"suffix",suffix},{"children",children}}));
 }
 Value readRows(const std::string& hash)const{
  auto node=get(hash);if(node.map.count("rows"))return node.at("rows");Value result=Value::dict();
  require(node.at("kind").text()=="entitiesBranch"||node.at("kind").text()=="projectionBranch","Artifact row kind");
  for(auto& child:node.at("children").map)for(auto& kv:readRows(child.second.text()).map)require(result.map.emplace(kv).second,"Artifact duplicate entity");return result;
 }
};
}
