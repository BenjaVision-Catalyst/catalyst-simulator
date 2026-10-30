#pragma once
#include "value.hpp"
#include <array>
#include <unordered_map>

namespace catalyst {
struct Identity {
 uint64_t high=0,low=0;
 bool operator<(const Identity& other)const{return high<other.high||(high==other.high&&low<other.low);}
 bool operator==(const Identity& other)const{return high==other.high&&low==other.low;}
 std::string text()const{std::ostringstream out;out<<std::hex<<std::setfill('0')<<std::setw(16)<<high<<std::setw(16)<<low;return out.str();}
 static Identity parse(const std::string& text){require(identifier(text),"Typed identity");return {std::stoull(text.substr(0,16),nullptr,16),std::stoull(text.substr(16),nullptr,16)};}
 template<class Archive>void serialize(Archive& ar,unsigned){ar&high&low;}
};
struct StringTable {
 std::vector<std::string> values;std::unordered_map<std::string,uint32_t> index;
 uint32_t intern(const std::string& value){require(value.size()<=4096,"Typed string width");for(unsigned char c:value)require(c>=32&&c<=126,"Typed string ASCII");auto found=index.find(value);if(found!=index.end())return found->second;require(values.size()<UINT32_MAX,"Typed string capacity");auto slot=uint32_t(values.size());values.push_back(value);index.emplace(value,slot);return slot;}
 const std::string& at(uint32_t slot)const{return values.at(slot);}
};
struct TypedRecord {
 Identity identity;std::array<int64_t,3> position{},velocity{},remainder{};int64_t quantity=0;uint32_t draw=0,sample=0,request=0,mode=0;
 Value value(const StringTable& strings)const{return Value::list({identity.text(),Value::list({Value(Integer(position[0])),Value(Integer(position[1])),Value(Integer(position[2]))}),Value::list({Value(Integer(velocity[0])),Value(Integer(velocity[1])),Value(Integer(velocity[2]))}),strings.at(request),Value(Integer(quantity)),strings.at(mode),Value(Integer(draw)),Value(Integer(sample)),Value::list({Value(Integer(remainder[0])),Value(Integer(remainder[1])),Value(Integer(remainder[2]))})});}
 static TypedRecord from(const Value& row,StringTable& strings){
  require(row.kind==Value::Array&&row.array.size()==9,"Typed row shape");TypedRecord record;record.identity=Identity::parse(row.at(0).text());
  for(int axis=0;axis<3;++axis){for(int field:{1,2,8})require(row.at(field).kind==Value::Array&&row.at(field).array.size()==3,"Typed vector shape");record.position[axis]=i64(row.at(1).at(axis).integer()).convert_to<int64_t>();record.velocity[axis]=i64(row.at(2).at(axis).integer()).convert_to<int64_t>();record.remainder[axis]=i64(row.at(8).at(axis).integer()).convert_to<int64_t>();require(record.remainder[axis]>=0&&record.remainder[axis]<1000,"Typed remainder");}
  record.quantity=nonnegative(row.at(4).integer()).convert_to<int64_t>();record.draw=u32(row.at(6).integer());record.sample=u32(row.at(7).integer());record.request=strings.intern(row.at(3).text());record.mode=strings.intern(row.at(5).text());return record;
 }
 void integrate(int64_t millis){auto nextPosition=position,nextRemainder=remainder;for(int axis=0;axis<3;++axis){Integer wide=Integer(velocity[axis])*millis+remainder[axis],delta=floorDiv(wide,Integer(1000));nextPosition[axis]=i64(Integer(position[axis])+delta).convert_to<int64_t>();nextRemainder[axis]=(wide-delta*1000).convert_to<int64_t>();}position=nextPosition;remainder=nextRemainder;}
};
static_assert(sizeof(TypedRecord)==112,"Qualified typed record layout");
// Wire codes are local to a rank. Text labels are re-interned at the receiver.
struct TypedWire {
 Identity identity;std::vector<int64_t> numbers;uint32_t draw=0,sample=0;std::string request,mode;
 TypedWire()=default;
 TypedWire(const TypedRecord& row,const StringTable& strings):identity(row.identity),draw(row.draw),sample(row.sample),request(strings.at(row.request)),mode(strings.at(row.mode)){for(auto value:row.position)numbers.push_back(value);for(auto value:row.velocity)numbers.push_back(value);for(auto value:row.remainder)numbers.push_back(value);numbers.push_back(row.quantity);}
 TypedRecord record(StringTable& strings)const{require(numbers.size()==10&&numbers[9]>=0,"Typed wire shape");TypedRecord row;row.identity=identity;for(int axis=0;axis<3;++axis){row.position[axis]=numbers[axis];row.velocity[axis]=numbers[axis+3];row.remainder[axis]=numbers[axis+6];require(row.remainder[axis]>=0&&row.remainder[axis]<1000,"Typed wire remainder");}row.quantity=numbers[9];row.draw=draw;row.sample=sample;row.request=strings.intern(request);row.mode=strings.intern(mode);return row;}
 template<class Archive>void serialize(Archive& ar,unsigned){ar&identity&numbers&draw&sample&request&mode;}
};
}
