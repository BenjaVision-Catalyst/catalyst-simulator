#pragma once
#include "value.hpp"
#include <set>
namespace catalyst {
inline Value registry;
inline bool matches(const Value& v,const std::string& type){
 if(type=="bool")return v.kind==Value::Boolean;
 if(type=="i64")return v.kind==Value::Number&&v.number>=MIN64&&v.number<=MAX64;
 if(type=="u32")return v.kind==Value::Number&&v.number>=0&&v.number<=MAX32;
 if(type=="string")return v.kind==Value::String;
 if(type=="vec3")return v.kind==Value::Array&&v.array.size()==3&&std::all_of(v.array.begin(),v.array.end(),[](const Value& x){return matches(x,"i64");});
 return false;
}
inline const std::vector<std::string> FIELDS={"id","position","velocity","requestedResource","requestedQuantity","mode","drawIndex","sample","motionRemainders"};
inline const std::vector<std::string> FIELD_TYPES={"string","vec3","vec3","string","i64","string","u32","u32","vec3"};
inline std::vector<Value> compileGraph(const Value& model){
 require(model.kind==Value::Array&&model.array.size()==6&&model.at(0).text()=="simulation-portable-1/graph-1","Unsupported model profile");
 require(!model.at(1).text().empty(),"Model identity");
 require(model.at(2).integer()>=1&&model.at(2).integer()<=1000,"Tick duration");
 for(int i:{3,4})require(model.at(i).integer()>=1&&model.at(i).integer()<=10000,"Model capacity");
 const auto& graph=model.at(5);require(graph.kind==Value::Map&&graph.map.size()==3&&graph.at("version").integer()==1,"Graph schema");
 auto budget=graph.at("maxNodeEvaluations").integer();require(budget>=1&&budget<=1000000,"Evaluation budget");
 require(graph.at("nodes").kind==Value::Array&&!graph.at("nodes").array.empty()&&graph.at("nodes").array.size()<=128,"Graph node bound");
 std::map<std::string,Value> byId;std::string last;size_t edges=0;
 const std::set<std::string> keys={"id","operation","version","stage","scope","type","inputs","after","parameters"};
 const std::map<std::string,int> costs={{"void",0},{"i64",22},{"u32",22},{"bool",1},{"string",4102},{"vec3",69}};
 for(auto& node:graph.at("nodes").array){
  require(node.kind==Value::Map&&node.map.size()==keys.size(),"Node schema");for(auto& k:keys)require(node.map.count(k),"Missing node field");
  std::string id=nodeText(node,"id");
  require(!id.empty()&&id.size()<=64&&id.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789-")==std::string::npos,"Node ID");
  require(last.empty()||last<id,"Model nodes must be normalized");last=id;
  require(byId.emplace(id,node).second,"Duplicate node");
  require(nodeText(node,"scope")=="world"||nodeText(node,"scope")=="entity","Node scope");stage(node);
  require(costs.count(nodeText(node,"type")),"Node type");
  for(auto key:{"inputs","after"}){require(node.at(std::string(key)).kind==Value::Array&&node.at(std::string(key)).array.size()<=32,"Dependency bound");edges+=node.at(std::string(key)).array.size();}
  std::string previous;for(auto& ref:node.at("after").array){require(previous.empty()||previous<ref.text(),"After order/duplicate");previous=ref.text();}
  require(node.at("parameters").kind==Value::Map&&node.at("parameters").map.size()<=8,"Parameter bound");
 }
 require(edges<=1024,"Edge budget");
 int worldNodes=0,entityNodes=0;Integer bytes=16;std::map<std::string,int> effects;
 for(auto& entry:byId){
  const auto& n=entry.second;auto path="model/graph/nodes/"+entry.first;auto op=nodeText(n,"operation");
  require(registry.map.count(op),"unsupported-operation: "+path+"/operation");const auto& d=registry.at(op);
  require(n.at("version")==d.at(0),"unsupported-version: "+path+"/version");
  require(d.at(1).text()=="either"||d.at(1).text()==nodeText(n,"scope"),"scope-mismatch: "+path+"/scope");
  require(d.at(2).text()=="any"||d.at(2).text()==nodeText(n,"stage"),"stage-mismatch: "+path+"/stage");
  require(n.at("inputs").array.size()==d.at(3).array.size(),"input-count: "+path+"/inputs");
  for(size_t i=0;i<n.at("inputs").array.size();++i){
   auto ref=n.at("inputs").at(i).text();require(byId.count(ref),"Missing dependency");
   require(nodeText(byId.at(ref),"type")==d.at(3).at(i).text(),"input-type: "+path+"/inputs/"+std::to_string(i+1));
   require(nodeText(n,"scope")=="entity"||nodeText(byId.at(ref),"scope")=="world","Entity value into world");
  }
  for(auto key:{"inputs","after"})for(auto& ref:n.at(std::string(key)).array){require(byId.count(ref.text()),"Missing dependency");require(stage(byId.at(ref.text()))<=stage(n),"Backward stage");}
  auto out=d.at(4).text();
  require(n.at("parameters").map.size()==d.at(5).map.size(),"parameter-schema: "+path+"/parameters");
  for(auto& p:d.at(5).map){
   require(n.at("parameters").map.count(p.first),"parameter-schema: "+path+"/parameters");
   auto type=p.second.text()=="declared"?nodeText(n,"type"):p.second.text();
   require(matches(n.at("parameters").at(p.first),type),"parameter-type: "+path+"/parameters/"+p.first);
  }
  if(out=="declared")out=nodeText(n,"type");
  if(out=="field"){
   auto it=std::find(FIELDS.begin(),FIELDS.end(),n.at("parameters").at("field").text());
   require(it!=FIELDS.end(),"output-type: "+path+"/type");out=FIELD_TYPES.at(size_t(it-FIELDS.begin()));
  }
  require(out==nodeText(n,"type"),"output-type: "+path+"/type");
  bool isWorld=nodeText(n,"scope")=="world";if(isWorld)++worldNodes;else ++entityNodes;
  int cost=costs.at(nodeText(n,"type"));if(cost)bytes+=100+(isWorld?Integer(cost):Integer(36+cost)*model.at(3).integer());
  ++effects[op];
 }
 require(effects["core.events.apply"]==1,"event-drain: model/graph/nodes");
 for(auto op:{"core.motion.integrate","core.resource.resolve","core.random.draw"})require(effects[op]<=1,"duplicate-effect: model/graph/nodes");
 require(worldNodes+entityNodes*model.at(3).integer()<=budget,"evaluation-budget: model/graph/maxNodeEvaluations");
 require(bytes<=67108864,"value-budget: model/graph/nodes");
 std::set<std::string> done;std::vector<Value> plan;
 while(done.size()<byId.size()){
  const Value* best=nullptr;
  for(auto& entry:byId)if(!done.count(entry.first)){
   const auto& n=entry.second;bool ready=true;
   for(auto key:{"inputs","after"})for(auto& ref:n.at(std::string(key)).array)if(!done.count(ref.text()))ready=false;
   if(ready&&(!best||stage(n)<stage(*best)||(stage(n)==stage(*best)&&entry.first<nodeText(*best,"id"))))best=&n;
  }
  require(best!=nullptr,"Cyclic graph");plan.push_back(*best);done.insert(nodeText(*best,"id"));
 }
 return plan;
}
}
