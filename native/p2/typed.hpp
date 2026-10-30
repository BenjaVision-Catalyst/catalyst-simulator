#pragma once
#include "population.hpp"
#ifdef __APPLE__
#include <mach/mach.h>
#endif
#include <sys/resource.h>
namespace catalyst {
struct TypedAgent {
 repast::AgentId id;TypedRecord row;
 TypedAgent(repast::AgentId identity,TypedRecord record):id(identity),row(record){}
 repast::AgentId& getId(){return id;}const repast::AgentId& getId()const{return id;}
};
struct TypedPackage {
 int ordinal=0,start=0,current=0;TypedWire data;
 template<class Archive>void serialize(Archive& ar,unsigned){ar&ordinal&start&current&data;}
};
struct TypedExchange {
 repast::SharedContext<TypedAgent>& context;StringTable& strings;
 void provideContent(repast::AgentRequest request,std::vector<TypedPackage>& packages){for(auto id:request.requestedAgents()){auto agent=context.getAgent(id);require(agent,"Missing typed migrant");packages.push_back({id.id(),id.startingRank(),id.currentRank(),TypedWire(agent->row,strings)});}}
 TypedAgent* createAgent(TypedPackage package){return new TypedAgent(repast::AgentId(package.ordinal,package.start,0,package.current),package.data.record(strings));}
 void updateAgent(TypedPackage package){auto agent=context.getAgent(repast::AgentId(package.ordinal,package.start,0));require(agent,"Missing typed update");agent->row=package.data.record(strings);agent->id.currentRank(package.current);}
};
class TypedProbe {
 mpi::communicator& world;StringTable strings;repast::SharedContext<TypedAgent> context;TypedExchange exchange;
 Value accepted,model;std::vector<Value> plan;std::map<std::string,Value> byId;std::string output;int layout;bool sharded=true;
 unsigned long shardedSnapshots=0,migrations=0,remoteRequests=0;
 int owner(const TypedRecord& row)const{auto result=(row.position[0]%world.size()+layout)%world.size();return int(result<0?result+world.size():result);}
 template<class F>void collectively(F function){std::string error;try{function();}catch(const std::exception& exception){error=exception.what();}int count=0;mpi::all_reduce(world,error.empty()?0:1,count,std::plus<int>());if(count){std::vector<std::string> errors;mpi::all_gather(world,error,errors);for(auto& item:errors)if(!item.empty())throw std::runtime_error(item);}}
 void validate(const Value& state,bool full){
  require(state.kind==Value::Map&&state.map.size()==9,"Checkpoint fields");for(auto key:{"version","model","modelDigest","tick","seed","entities","resources","events","outcomes"})require(state.map.count(key),"Missing checkpoint field");
  require(state.at("version").integer()==2&&state.at("model")==model,"Checkpoint schema/model mismatch");
  require(state.at("modelDigest").text()==sha256("CatalystSimulation-Model-1:"+encode(model)),"Model digest mismatch");
  nonnegative(state.at("tick").integer());require(state.at("seed").integer()>=0&&state.at("seed").integer()<=MAXU64,"Seed bound");
  require(state.at("entities").kind==Value::Map&&state.at("entities").map.size()<=model.at(3).integer(),"Entity bound");
  require(state.at("resources").kind==Value::Map&&state.at("resources").map.size()<=model.at(3).integer(),"Resource map/bound");
  for(auto& kv:state.at("resources").map){require(!kv.first.empty(),"Empty resource name");nonnegative(kv.second.integer());}
  for(auto& kv:state.at("entities").map){
   auto& e=kv.second;require(identifier(kv.first)&&e.kind==Value::Array&&e.array.size()==9&&e.at(0).text()==kv.first,"Entity record");
   for(int index:{1,2,8}){require(e.at(index).kind==Value::Array&&e.at(index).array.size()==3,"Vector shape");for(auto& v:e.at(index).array)i64(v.integer());}
   for(auto& r:e.at(8).array)require(r.integer()>=0&&r.integer()<1000,"Motion remainder");
   require(e.at(3).kind==Value::String&&e.at(5).kind==Value::String,"Entity strings");
   nonnegative(e.at(4).integer());require(e.at(4).integer()==0||state.at("resources").map.count(e.at(3).text()),"Resource reference");u32(e.at(6).integer());u32(e.at(7).integer());
  }
  const auto& q=state.at("events");require(q.kind==Value::Array&&q.array.size()==4&&q.at(3).integer()==model.at(4).integer(),"Event queue shape");
  require(q.at(0).kind==Value::Array&&q.at(1).kind==Value::Map&&q.at(0).array.size()<=model.at(4).integer()&&q.at(1).map.size()<=model.at(4).integer(),"Event bound");nonnegative(q.at(2).integer());std::set<std::string> sequence;
  for(auto& g:q.at(1).map){require(identifier(g.first),"Event ID");nonnegative(g.second.integer());}
  for(auto& e:q.at(0).array){
   require(e.kind==Value::Array&&e.array.size()==8,"Event record");nonnegative(e.at(0).integer());
   require(e.at(0).integer()>state.at("tick").integer()&&e.at(1).integer()==0&&e.at(2).integer()==0,"Event time/phase");
   require(identifier(e.at(3).text())&&identifier(e.at(5).text()),"Event identity");
   require(e.at(4).integer()>0&&e.at(4).integer()<=q.at(2).integer()&&sequence.insert(encode(e.at(4))).second,"Event sequence");
   nonnegative(e.at(6).integer());require(q.at(1).map.count(e.at(5).text())&&e.at(6).integer()<=q.at(1).at(e.at(5).text()).integer(),"Event generation");require(e.at(7).kind==Value::String,"Event mode");
   if(full)require(state.at("entities").map.count(e.at(3).text()),"Event target");
  }
  require(state.at("outcomes").kind==Value::Array&&state.at("outcomes").array.size()<=model.at(3).integer(),"Outcome bound");
  for(auto& o:state.at("outcomes").array){require(o.kind==Value::Array&&o.array.size()==4&&o.at(0)==state.at("tick"),"Outcome time/shape");nonnegative(o.at(3).integer());require(state.at("resources").map.count(o.at(1).text()),"Outcome resource");if(full)require(state.at("entities").map.count(o.at(2).text()),"Outcome entity");}
  if(!sharded)encode(state);else for(auto& kv:state.at("entities").map)encode(kv.second);
 }
 Value expression(const Value& node,const std::vector<Value>& input,const Value& metadata,const TypedRecord* row){
  auto operation=nodeText(node,"operation");const auto& parameters=node.at("parameters");
  if(operation=="core.constant")return parameters.at("value");
  if(operation=="core.tick")return metadata.at("tick");
  if(operation=="core.entity.field"){auto found=std::find(FIELDS.begin(),FIELDS.end(),parameters.at("field").text());require(found!=FIELDS.end()&&row,"Typed field");return row->value(strings).at(size_t(found-FIELDS.begin()));}
  if(operation=="core.i64.add")return Value(i64(input.at(0).integer()+input.at(1).integer()));
  if(operation=="core.i64.less")return Value(input.at(0).integer()<input.at(1).integer());
  if(operation=="core.select.i64")return input.at(input.at(0).truth()?1:2);
  if(operation=="core.string.equal")return Value(input.at(0).text()==input.at(1).text());
  if(operation=="core.bool.and")return Value(input.at(0).truth()&&input.at(1).truth());
  if(operation=="core.bool.not")return Value(!input.at(0).truth());throw std::runtime_error("Unknown typed expression");
 }
 void effect(const Value& node,const std::vector<Value>& input,Value& metadata,TypedRecord& row){
  if(!input.at(0).truth())return;auto operation=nodeText(node,"operation");
  if(operation=="core.motion.integrate"){row.integrate(model.at(2).integer().convert_to<int64_t>());return;}
  if(operation=="core.random.draw"){auto next=u32(Integer(row.draw)+1);row.sample=sample(row.identity.text(),metadata.at("seed").integer(),u32(node.at("parameters").at("stream").integer()),row.draw);row.draw=next;return;}
  auto value=row.value(strings);
  if(operation=="core.velocity.set")value.at(2)=input.at(1);
  else if(operation=="core.mode.set")value.at(5)=input.at(1);
  else if(operation=="core.resource.request"){auto quantity=nonnegative(input.at(2).integer());require(quantity==0||metadata.at("resources").map.count(input.at(1).text()),"Typed resource reference");value.at(3)=input.at(1);value.at(4)=Value(quantity);}
  else throw std::runtime_error("Unknown typed effect");row=TypedRecord::from(value,strings);
 }
 void events(Value& metadata,std::vector<TypedRecord>& rows,const std::map<Identity,size_t>& index){
  std::string updates;collectively([&]{if(world.rank()!=0)return;Value changes=Value::list(),future=Value::list();auto& queue=metadata.at("events");auto sorted=queue.at(0).array;std::sort(sorted.begin(),sorted.end(),lex);
   for(auto& event:sorted)if(event.at(6)==queue.at(1).at(event.at(5).text())){if(event.at(0).integer()<=metadata.at("tick").integer())changes.array.push_back(event);else future.array.push_back(event);}queue.at(0)=future;updates=encode(Value::list({queue,changes}));});
  mpi::broadcast(world,updates,0);auto data=decode(updates);metadata.at("events")=data.at(0);
  collectively([&]{for(auto& event:data.at(1).array){auto found=index.find(Identity::parse(event.at(3).text()));if(found!=index.end())rows[found->second].mode=strings.intern(event.at(7).text());}});
 }
 void resolve(Value& metadata,std::vector<TypedRecord>& rows,const std::map<Identity,size_t>& index){
  Value requests=Value::list();for(auto& row:rows)if(row.quantity>0){requests.array.push_back(Value::list({row.identity.text(),strings.at(row.request),Value(Integer(row.quantity))}));if(world.rank()!=0)++remoteRequests;}
  std::vector<std::string> all;mpi::gather(world,encode(requests),all,0);std::string response;
  collectively([&]{if(world.rank()!=0)return;std::vector<Value> ordered;for(auto& shard:all)for(auto& request:decode(shard).array)ordered.push_back(request);std::sort(ordered.begin(),ordered.end(),lex);Value grants=Value::list();
   for(auto& request:ordered){auto& stock=metadata.at("resources").at(request.at(1).text());if(stock.integer()>=request.at(2).integer()){stock=Value(stock.integer()-request.at(2).integer());grants.array.push_back(Value::list({metadata.at("tick"),request.at(1),request.at(0),request.at(2)}));}}response=encode(Value::list({metadata.at("resources"),grants}));});
  mpi::broadcast(world,response,0);auto data=decode(response);metadata.at("resources")=data.at(0);metadata.at("outcomes")=data.at(1);
  for(auto& grant:data.at(1).array){auto found=index.find(Identity::parse(grant.at(2).text()));if(found!=index.end())rows[found->second].quantity=0;}
 }
public:
 TypedProbe(mpi::communicator& communicator,const std::string& objects,const std::string& root,const std::string& directory,int offset):world(communicator),context(&communicator),exchange{context,strings},output(directory),layout(offset){
  CasStore store(objects);auto manifest=store.get(root);require(manifest.at("kind").text()=="checkpoint"&&manifest.at("version").integer()==1,"Typed manifest");model=store.readValue(manifest.at("model").text());require(model.at(0).text()=="simulation-portable-1/typed-1","Typed profile");plan=compileGraph(model);for(auto& node:plan)byId[nodeText(node,"id")]=node;
  accepted=Value::dict({{"version",Value(2)},{"model",model},{"modelDigest",manifest.at("modelDigest")},{"tick",manifest.at("tick")},{"seed",manifest.at("seed")},{"entities",Value::dict()},{"resources",store.readValue(manifest.at("resources").text())},{"events",store.readValue(manifest.at("events").text())},{"outcomes",store.readValue(manifest.at("outcomes").text())}});
  collectively([&]{validate(accepted,false);});
  std::vector<std::vector<TypedWire>> send(world.size()),receive;
  collectively([&]{for(auto& bucket:store.readIndex(manifest.at("entities").text()).map)if(std::stoi(bucket.first,nullptr,16)%world.size()==world.rank())for(auto& item:store.readRows(bucket.second.text()).map){auto record=TypedRecord::from(item.second,strings);require(record.identity.text()==item.first&&item.first.substr(30)==bucket.first,"Typed row identity/bucket");require(record.quantity==0||accepted.at("resources").map.count(strings.at(record.request)),"Typed resource reference");send[owner(record)].emplace_back(record,strings);}});
  mpi::all_to_all(world,send,receive);int ordinal=0;std::set<Identity> unique;
  collectively([&]{for(auto& shard:receive)for(auto& wire:shard){auto row=wire.record(strings);require(unique.insert(row.identity).second,"Duplicate typed entity");context.addAgent(new TypedAgent(repast::AgentId(ordinal++,world.rank(),0,world.rank()),row));}});
  unsigned long local=unique.size(),total=0;mpi::all_reduce(world,local,total,std::plus<unsigned long>());require(Integer(total)==manifest.at("entityCount").integer()&&Integer(total)<=model.at(3).integer(),"Typed population count");std::vector<Identity> references;for(auto& event:accepted.at("events").at(0).array)references.push_back(Identity::parse(event.at(3).text()));for(auto& outcome:accepted.at("outcomes").array)references.push_back(Identity::parse(outcome.at(2).text()));for(auto& identity:references){int present=unique.count(identity),found=0;mpi::all_reduce(world,present,found,std::plus<int>());require(found==1,"Typed metadata entity reference");}if(world.rank()==0)std::filesystem::create_directories(output);
 }
 Integer tick()const{return accepted.at("tick").integer();}
 unsigned long snapshotCount()const{return 0;}
 unsigned long shardedSnapshotCount()const{return shardedSnapshots;}
 std::string checkpoint(){throw std::runtime_error("Typed populations require sharded checkpoint artifacts");}
 Value populationStatistics(){
  unsigned long count=0;for(auto it=context.localBegin();it!=context.localEnd();++it)++count;std::vector<unsigned long> counts,rss,peaks;unsigned long resident=0;struct rusage usage{};getrusage(RUSAGE_SELF,&usage);
#ifdef __APPLE__
  mach_task_basic_info_data_t info;mach_msg_type_number_t size=MACH_TASK_BASIC_INFO_COUNT;if(task_info(mach_task_self(),MACH_TASK_BASIC_INFO,(task_info_t)&info,&size)==KERN_SUCCESS)resident=info.resident_size;
#endif
  mpi::all_gather(world,count,counts);mpi::all_gather(world,resident,rss);mpi::all_gather(world,(unsigned long)usage.ru_maxrss,peaks);
  auto list=[](const std::vector<unsigned long>& values){auto result=Value::list();for(auto value:values)result.array.emplace_back(Integer(value));return result;};
  return Value::dict({{"layout","typed-records-1"},{"rowBytes",Value(int(sizeof(TypedRecord)))},{"persistentBoxedPopulationRows",Value(0)},{"localCounts",list(counts)},{"currentRssBytes",list(rss)},{"peakRssBytes",list(peaks)}});
 }
 std::string shardedCheckpoint(const std::string& objects){
  ++shardedSnapshots;CasStore store(objects);std::vector<std::vector<TypedWire>> send(world.size()),receive;
  for(auto it=context.localBegin();it!=context.localEnd();++it){const auto& row=(*it)->row;send[(row.identity.low&255)%world.size()].emplace_back(row,strings);}mpi::all_to_all(world,send,receive);
  std::map<std::string,std::vector<TypedRecord>> grouped;unsigned long local=0;
  collectively([&]{for(auto& shard:receive)for(auto& wire:shard){auto row=wire.record(strings);grouped[row.identity.text().substr(30)].push_back(row);++local;}});
  Value descriptor=Value::list({Value::dict(),Value::dict()});
  collectively([&]{for(auto& bucket:grouped){Value rows=Value::dict(),poses=Value::dict();for(auto& row:bucket.second){auto id=row.identity.text();auto value=row.value(strings);require(rows.map.emplace(id,value).second,"Duplicate typed checkpoint row");poses.map.emplace(id,Value::list({value.at(0),value.at(1),value.at(2),value.at(5)}));}descriptor.at(0).map[bucket.first]=store.rows(rows,bucket.first,false);descriptor.at(1).map[bucket.first]=store.rows(poses,bucket.first,true);}});
  std::vector<std::string> descriptors;mpi::gather(world,encode(descriptor),descriptors,0);unsigned long total=0;mpi::reduce(world,local,total,std::plus<unsigned long>(),0);std::string root;
  collectively([&]{if(world.rank()!=0)return;Value entities=Value::dict(),projection=Value::dict();for(auto& raw:descriptors){auto value=decode(raw);for(auto& item:value.at(0).map)require(entities.map.emplace(item).second,"Duplicate typed bucket");for(auto& item:value.at(1).map)require(projection.map.emplace(item).second,"Duplicate typed projection bucket");}
   root=store.put(Value::dict({{"kind","checkpoint"},{"version",Value(1)},{"model",store.value(model)},{"modelDigest",accepted.at("modelDigest")},{"tick",accepted.at("tick")},{"seed",accepted.at("seed")},{"entities",store.index(entities)},{"projection",store.index(projection)},{"entityCount",Value(Integer(total))},{"resources",store.value(accepted.at("resources"))},{"events",store.value(accepted.at("events"))},{"outcomes",store.value(accepted.at("outcomes"))}}));});mpi::broadcast(world,root,0);return root;
 }
 void advance(){
  Value candidate=accepted;candidate.at("outcomes")=Value::list();collectively([&]{candidate.at("tick")=Value(nonnegative(tick()+1));});
  std::vector<TypedAgent*> agents;for(auto it=context.localBegin();it!=context.localEnd();++it)agents.push_back((*it).get());std::sort(agents.begin(),agents.end(),[](auto a,auto b){return a->row.identity<b->row.identity;});
  std::vector<TypedRecord> rows;std::map<Identity,size_t> index;for(auto agent:agents){index.emplace(agent->row.identity,rows.size());rows.push_back(agent->row);}
  std::map<std::string,std::vector<Value>> entityValues;std::map<std::string,Value> worldValues;int previous=-1;std::vector<TypedRecord> read;Value readMetadata;
  for(auto& node:plan){if(stage(node)!=previous){previous=stage(node);read=rows;readMetadata=candidate;}
   auto operation=nodeText(node,"operation"),id=nodeText(node,"id");if(operation=="core.events.apply"){events(candidate,rows,index);continue;}if(operation=="core.resource.resolve"){resolve(candidate,rows,index);continue;}
   bool isWorld=nodeText(node,"scope")=="world",isVoid=nodeText(node,"type")=="void";std::vector<Value> result;std::string broadcast;
   collectively([&]{size_t count=isWorld?(world.rank()==0?1:0):rows.size();if(!isWorld&&!isVoid)result.reserve(count);
    for(size_t slot=0;slot<count;++slot){std::vector<Value> arguments;for(auto& ref:node.at("inputs").array)arguments.push_back(nodeText(byId.at(ref.text()),"scope")=="world"?worldValues.at(ref.text()):entityValues.at(ref.text()).at(slot));
     if(isVoid){require(!isWorld,"Unknown typed world effect");effect(node,arguments,candidate,rows[slot]);}else{auto value=expression(node,arguments,readMetadata,isWorld?nullptr:&read[slot]);if(isWorld)broadcast=encode(value);else result.push_back(std::move(value));}}
   });
   if(!isVoid){if(isWorld){mpi::broadcast(world,broadcast,0);worldValues[id]=decode(broadcast);}else entityValues[id]=std::move(result);}
  }
  collectively([&]{validate(candidate,false);});accepted=std::move(candidate);for(size_t slot=0;slot<agents.size();++slot)agents[slot]->row=rows[slot];
  for(auto agent:agents){int target=owner(agent->row);if(target!=world.rank()){repast::RepastProcess::instance()->moveAgent(agent->id,target);++migrations;}}
  repast::RepastProcess::instance()->synchronizeAgentStatus<TypedAgent,TypedPackage,TypedExchange,TypedExchange,TypedExchange>(context,exchange,exchange,exchange);
 }
 void finish(){unsigned long moves=0,requests=0;mpi::reduce(world,migrations,moves,std::plus<unsigned long>(),0);mpi::reduce(world,remoteRequests,requests,std::plus<unsigned long>(),0);auto stats=populationStatistics();if(world.rank()==0){stats.map["migrations"]=Value(Integer(moves));stats.map["remoteRequests"]=Value(Integer(requests));publish(output+"/execution.canon",encode(stats));}}
};
}
