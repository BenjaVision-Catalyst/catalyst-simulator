#pragma once
#include <boost/multiprecision/cpp_int.hpp>
#include <openssl/sha.h>
#include <algorithm>
#include <cstdint>
#include <fstream>
#include <iomanip>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
namespace catalyst {
using Integer = boost::multiprecision::cpp_int;
inline void require(bool condition,const std::string& message){if(!condition)throw std::runtime_error(message);}
struct Value {
  enum Kind { Nil, Boolean, Number, String, Array, Map } kind=Nil;
  bool boolean=false; Integer number=0; std::string string;
  std::vector<Value> array;std::map<std::string,Value> map;
  Value()=default;Value(bool x):kind(Boolean),boolean(x){} Value(int x):kind(Number),number(x){}
  Value(const Integer& x):kind(Number),number(x){} Value(const std::string& x):kind(String),string(x){}
  Value(const char* x):Value(std::string(x)){}
  static Value list(std::vector<Value> x={}){Value v;v.kind=Array;v.array=std::move(x);return v;}
  static Value dict(std::map<std::string,Value> x={}){Value v;v.kind=Map;v.map=std::move(x);return v;}
  Value& at(size_t i){require(kind==Array&&i<array.size(),"Array index");return array.at(i);}
  const Value& at(size_t i)const{require(kind==Array&&i<array.size(),"Array index");return array.at(i);}
  Value& at(const std::string& k){require(kind==Map,"Map required");return map.at(k);}
  const Value& at(const std::string& k)const{require(kind==Map,"Map required");return map.at(k);}
  std::string text()const{require(kind==String,"String required");return string;}
  Integer integer()const{require(kind==Number,"Integer required");return number;}
  bool truth()const{require(kind==Boolean,"Boolean required");return boolean;}
  bool operator==(const Value& b)const{return kind==b.kind&&(kind==Nil||(kind==Boolean&&boolean==b.boolean)||(kind==Number&&number==b.number)||(kind==String&&string==b.string)||(kind==Array&&array==b.array)||(kind==Map&&map==b.map));}
};
inline const Integer MIN64=-(Integer(1)<<63),MAX64=(Integer(1)<<63)-1,MAX32=(Integer(1)<<32)-1,MAXU64=(Integer(1)<<64)-1;
inline Integer i64(Integer x){require(x>=MIN64&&x<=MAX64,"Signed 64-bit overflow");return x;}
inline Integer nonnegative(Integer x){i64(x);require(x>=0,"Negative quantity/tick");return x;}
inline uint32_t u32(const Integer& x){require(x>=0&&x<=MAX32,"Unsigned 32-bit overflow");return x.convert_to<uint32_t>();}
inline Integer floorDiv(Integer x,const Integer& divisor){Integer q=x/divisor,r=x%divisor;if(r<0)--q;return q;}
inline bool identifier(const std::string& id){return id.size()==32&&id.find_first_not_of("0123456789abcdef")==std::string::npos;}
inline std::string encode(const Value& v){
 size_t atoms=0;std::string out;
 auto write=[&](auto&& self,const Value& x,size_t depth)->void{
  require(++atoms<=500000&&depth<=16&&out.size()<=8388608,"Canonical value budget");
  switch(x.kind){
   case Value::Nil:out+='n';break;
   case Value::Boolean:out+=x.boolean?'t':'f';break;
   case Value::Number:require(x.number>=MIN64&&x.number<=MAXU64,"Canonical integer bound");out+='i';out+=x.number.convert_to<std::string>();out+=';';break;
   case Value::String:require(x.string.size()<=4096&&std::all_of(x.string.begin(),x.string.end(),[](unsigned char c){return c>=32&&c<=126;}),"Printable ASCII required");out+='s';out+=std::to_string(x.string.size());out+=':';out+=x.string;break;
   case Value::Array:require(x.array.size()<=100000,"Array bound");out+='a';out+=std::to_string(x.array.size());out+=':';for(auto& item:x.array)self(self,item,depth+1);break;
   case Value::Map:require(x.map.size()<=100000,"Map bound");out+='d';out+=std::to_string(x.map.size());out+=':';for(auto& item:x.map){self(self,Value(item.first),depth+1);self(self,item.second,depth+1);}break;
  }
 };write(write,v,0);require(out.size()<=8388608,"Canonical byte budget");return out;
}
inline Value decode(const std::string& text){
 require(text.size()<=8388608,"Canonical byte budget");size_t pos=0,atoms=0;
 auto take=[&](){require(pos<text.size(),"Truncated input");return text[pos++];};
 auto decimal=[&](char delimiter){Integer n=0;bool negative=false;size_t count=0;char c=take();if(c=='-'){negative=true;c=take();}while(c!=delimiter){require(c>='0'&&c<='9'&&++count<=20,"Invalid decimal");n=n*10+(c-'0');c=take();}require(count>0,"Empty decimal");return Integer(negative?-n:n);};
 auto read=[&](auto&& self,size_t depth)->Value{
  require(++atoms<=500000&&depth<=16,"Canonical value budget");char tag=take();
  if(tag=='n')return Value();if(tag=='t'||tag=='f')return Value(tag=='t');if(tag=='i')return Value(decimal(';'));
  Integer count=decimal(':');require(count>=0&&count<=100000,"Collection bound");size_t n=count.convert_to<size_t>();
  if(tag=='s'){require(n<=4096&&pos+n<=text.size(),"String bound");Value x(text.substr(pos,n));pos+=n;return x;}
  if(tag=='a'){Value x=Value::list();for(size_t i=0;i<n;++i)x.array.push_back(self(self,depth+1));return x;}
  if(tag=='d'){Value x=Value::dict();for(size_t i=0;i<n;++i){std::string k=self(self,depth+1).text();require(!x.map.count(k),"Duplicate key");x.map[k]=self(self,depth+1);}return x;}
  throw std::runtime_error("Unknown canonical tag");
 };Value value=read(read,0);require(pos==text.size()&&encode(value)==text,"Noncanonical input");return value;
}
inline std::string sha256(const std::string& bytes){unsigned char d[SHA256_DIGEST_LENGTH];SHA256(reinterpret_cast<const unsigned char*>(bytes.data()),bytes.size(),d);std::ostringstream out;out<<std::hex<<std::setfill('0');for(unsigned char c:d)out<<std::setw(2)<<unsigned(c);return out.str();}
inline std::string readFile(const std::string& path){std::ifstream stream(path,std::ios::binary);require(bool(stream),"Cannot read "+path);std::ostringstream out;out<<stream.rdbuf();return out.str();}
inline void publish(const std::string& path,const std::string& bytes){{std::ofstream stream(path+".tmp",std::ios::binary);require(bool(stream),"Cannot write "+path);stream<<bytes;stream.close();require(bool(stream),"Write failed");}require(std::rename((path+".tmp").c_str(),path.c_str())==0,"Atomic rename failed");}
inline uint32_t sample(const std::string& id,const Integer& seed,uint32_t stream,uint32_t draw){
 require(identifier(id)&&seed>=0&&seed<=MAXU64,"Random address bound");Integer entity=0;for(char c:id)entity=entity*16+std::string("0123456789abcdef").find(c);
 uint32_t c[4]={draw,stream,u32(entity&MAX32),u32((entity>>32)&MAX32)},k[2]={u32((entity>>64)&MAX32)^u32(seed&MAX32),u32((entity>>96)&MAX32)^u32((seed>>32)&MAX32)};
 for(int round=0;round<10;++round){uint64_t p0=uint64_t(0xD2511F53u)*c[0],p1=uint64_t(0xCD9E8D57u)*c[2];uint32_t next[4]={uint32_t(p1>>32)^c[1]^k[0],uint32_t(p1),uint32_t(p0>>32)^c[3]^k[1],uint32_t(p0)};std::copy(next,next+4,c);k[0]+=0x9E3779B9u;k[1]+=0xBB67AE85u;}return c[0];
}
inline std::string nodeText(const Value& node,const char* key){return node.at(std::string(key)).text();}
inline const std::vector<std::string> STAGES={"events","decide","motion","resolve","random"};
inline int stage(const Value& node){auto it=std::find(STAGES.begin(),STAGES.end(),nodeText(node,"stage"));require(it!=STAGES.end(),"Unknown stage");return int(it-STAGES.begin());}
inline bool lex(const Value& a,const Value& b){require(a.kind==b.kind,"Mixed ordering types");if(a.kind==Value::Number)return a.number<b.number;if(a.kind==Value::String)return a.string<b.string;require(a.kind==Value::Array,"Unsupported order");return std::lexicographical_compare(a.array.begin(),a.array.end(),b.array.begin(),b.array.end(),lex);}
} // namespace catalyst
