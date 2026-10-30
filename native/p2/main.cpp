#include "graph.hpp"
#include <repast_hpc/RepastProcess.h>
#include <repast_hpc/SharedContext.h>
#include <repast_hpc/Schedule.h>
#include <boost/mpi.hpp>
#include <boost/serialization/string.hpp>
#include <boost/serialization/vector.hpp>
#include <filesystem>
#include <thread>
#include <chrono>
using namespace catalyst;
namespace mpi=boost::mpi;
struct Agent {
 repast::AgentId id;Value row;
 Agent(repast::AgentId identity,Value data):id(identity),row(std::move(data)){}
 repast::AgentId& getId(){return id;} const repast::AgentId& getId()const{return id;}
};
struct Package {
 int ordinal=0,start=0,type=0,current=0;std::string data;
 template<class Archive>void serialize(Archive& ar,unsigned){ar&ordinal&start&type&current&data;}
};
struct Exchange {
 repast::SharedContext<Agent>& context;
 void provideContent(repast::AgentRequest request,std::vector<Package>& packages){for(auto id:request.requestedAgents()){Agent* a=context.getAgent(id);require(a!=nullptr,"Missing migrating agent");packages.push_back({id.id(),id.startingRank(),id.agentType(),a->id.currentRank(),encode(a->row)});}}
 Agent* createAgent(Package p){return new Agent(repast::AgentId(p.ordinal,p.start,p.type,p.current),decode(p.data));}
 void updateAgent(Package p){Agent* a=context.getAgent(repast::AgentId(p.ordinal,p.start,p.type));require(a!=nullptr,"Missing update agent");a->row=decode(p.data);a->id.currentRank(p.current);}
};
class Probe {
 mpi::communicator& world;repast::SharedContext<Agent> context;Exchange exchange;
 Value accepted,model;std::vector<Value> plan;std::map<std::string,Value> byId;
 std::string output;int layout,holdTick;unsigned long migrations=0,remoteRequests=0;
 int owner(const Value& row)const{Integer r=(floorDiv(row.at(1).at(0).integer(),Integer(1))+layout)%world.size();if(r<0)r+=world.size();return r.convert_to<int>();}
 Value rows()const{Value out=Value::dict();for(auto it=context.localBegin();it!=context.localEnd();++it)out.map[(*it)->row.at(0).text()]=(*it)->row;return out;}
 void consensus(const std::string& error){int count=0;mpi::all_reduce(world,error.empty()?0:1,count,std::plus<int>());if(count){std::vector<std::string> errors;mpi::all_gather(world,error,errors);for(auto& e:errors)if(!e.empty())throw std::runtime_error(e);}}
 template<class F>void collectively(F function){std::string error;try{function();}catch(const std::exception& e){error=e.what();}consensus(error);}
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
  encode(state);
 }
 Value valueNode(const Value& n,const std::vector<Value>& in,const Value& read,const std::string& id){
  auto op=nodeText(n,"operation");const auto& p=n.at("parameters");
  if(op=="core.constant")return p.at("value");if(op=="core.tick")return read.at("tick");
  if(op=="core.entity.field"){auto it=std::find(FIELDS.begin(),FIELDS.end(),p.at("field").text());require(it!=FIELDS.end(),"Unknown field");return read.at("entities").at(id).at(size_t(it-FIELDS.begin()));}
  if(op=="core.i64.add")return Value(i64(in.at(0).integer()+in.at(1).integer()));
  if(op=="core.i64.less")return Value(in.at(0).integer()<in.at(1).integer());
  if(op=="core.select.i64")return in.at(in.at(0).truth()?1:2);
  if(op=="core.string.equal")return Value(in.at(0).text()==in.at(1).text());
  if(op=="core.bool.and")return Value(in.at(0).truth()&&in.at(1).truth());
  if(op=="core.bool.not")return Value(!in.at(0).truth());throw std::runtime_error("Unknown value operation");
 }
 void effect(const Value& n,const std::vector<Value>& in,Value& state,const std::string& id){
  if(!in.at(0).truth())return;auto& e=state.at("entities").at(id);auto op=nodeText(n,"operation");
  if(op=="core.velocity.set")e.at(2)=in.at(1);
  else if(op=="core.mode.set")e.at(5)=in.at(1);
  else if(op=="core.resource.request"){nonnegative(in.at(2).integer());e.at(3)=in.at(1);e.at(4)=in.at(2);}
  else if(op=="core.motion.integrate")for(int axis=0;axis<3;++axis){Integer wide=e.at(2).at(axis).integer()*model.at(2).integer()+e.at(8).at(axis).integer(),delta=floorDiv(wide,Integer(1000));e.at(1).at(axis)=Value(i64(e.at(1).at(axis).integer()+delta));e.at(8).at(axis)=Value(wide-delta*1000);}
  else if(op=="core.random.draw"){uint32_t draw=u32(e.at(6).integer()),stream=u32(n.at("parameters").at("stream").integer());e.at(7)=Value(Integer(sample(id,state.at("seed").integer(),stream,draw)));e.at(6)=Value(Integer(u32(Integer(draw)+1)));}
  else throw std::runtime_error("Unknown effect operation");
 }
 void events(Value& state){
  std::string updates;
  collectively([&]{if(world.rank()==0){Value changes=Value::list(),future=Value::list();auto& q=state.at("events");auto sorted=q.at(0).array;std::sort(sorted.begin(),sorted.end(),lex);
   for(auto& e:sorted)if(e.at(6)==q.at(1).at(e.at(5).text())){if(e.at(0).integer()<=state.at("tick").integer())changes.array.push_back(e);else future.array.push_back(e);}
   q.at(0)=future;updates=encode(Value::list({q,changes}));}});
  mpi::broadcast(world,updates,0);Value data=decode(updates);state.at("events")=data.at(0);
  for(auto& e:data.at(1).array){auto it=state.at("entities").map.find(e.at(3).text());if(it!=state.at("entities").map.end())it->second.at(5)=e.at(7);}
 }
 void resolve(Value& state){
  Value requests=Value::list();for(auto& kv:state.at("entities").map)if(kv.second.at(4).integer()>0){requests.array.push_back(Value::list({kv.first,kv.second.at(3),kv.second.at(4)}));if(world.rank()!=0)++remoteRequests;}
  std::vector<std::string> all;mpi::gather(world,encode(requests),all,0);std::string response;
  collectively([&]{if(world.rank()==0){std::vector<Value> ordered;for(auto& shard:all)for(auto& r:decode(shard).array)ordered.push_back(r);std::sort(ordered.begin(),ordered.end(),lex);Value grants=Value::list();
   for(auto& r:ordered){auto& stock=state.at("resources").at(r.at(1).text());if(stock.integer()>=r.at(2).integer()){stock=Value(stock.integer()-r.at(2).integer());grants.array.push_back(Value::list({state.at("tick"),r.at(1),r.at(0),r.at(2)}));}}response=encode(Value::list({state.at("resources"),grants}));}});
  mpi::broadcast(world,response,0);Value data=decode(response);state.at("resources")=data.at(0);state.at("outcomes")=data.at(1);
  for(auto& g:data.at(1).array){auto it=state.at("entities").map.find(g.at(2).text());if(it!=state.at("entities").map.end())it->second.at(4)=Value(0);}
 }
public:
 Probe(mpi::communicator& comm,const std::string& checkpoint,const std::string& bundle,const std::string& directory,int offset,int hold):
  world(comm),context(&comm),exchange{context},accepted(decode(checkpoint)),model(decode(bundle)),output(directory),layout(offset),holdTick(hold){
  plan=compileGraph(model);for(auto& n:plan)byId[nodeText(n,"id")]=n;validate(accepted,true);
  int ordinal=0;for(auto& kv:accepted.at("entities").map){int rank=owner(kv.second);if(rank==world.rank())context.addAgent(new Agent(repast::AgentId(ordinal,0,0,rank),kv.second));++ordinal;}
  accepted.at("entities")=rows();if(world.rank()==0)std::filesystem::create_directories(output);writeAccepted();
 }
 void writeAccepted(){
  std::vector<std::string> shards;mpi::gather(world,encode(rows()),shards,0);
  collectively([&]{if(world.rank()!=0)return;Value all=accepted;all.at("entities")=Value::dict();
   for(auto& shard:shards)for(auto& kv:decode(shard).map)require(all.at("entities").map.emplace(kv.first,kv.second).second,"Duplicate owned entity");
   validate(all,true);auto bytes=encode(all),tick=all.at("tick").integer().convert_to<std::string>();publish(output+"/tick-"+tick+".canon",bytes);publish(output+"/accepted.canon",bytes);});
 }
 void advance(){
  Value candidate=accepted;candidate.at("entities")=rows();candidate.at("outcomes")=Value::list();
  collectively([&]{candidate.at("tick")=Value(nonnegative(accepted.at("tick").integer()+1));});
  std::map<std::string,Value> values;int previousStage=-1;Value read;
  for(auto& n:plan){
   if(previousStage!=stage(n)){previousStage=stage(n);read=candidate;}
   auto op=nodeText(n,"operation"),nid=nodeText(n,"id");
   if(op=="core.events.apply"){events(candidate);continue;}if(op=="core.resource.resolve"){resolve(candidate);continue;}
   bool isWorld=nodeText(n,"scope")=="world",isVoid=nodeText(n,"type")=="void";Value result=Value::dict();std::string broadcast;
   collectively([&]{std::vector<std::string> ids;if(isWorld){if(world.rank()==0)ids.push_back("");}else for(auto& kv:candidate.at("entities").map)ids.push_back(kv.first);
    for(auto& id:ids){std::vector<Value> args;for(auto& ref:n.at("inputs").array){const auto& v=values.at(ref.text());args.push_back(nodeText(byId.at(ref.text()),"scope")=="world"?v:v.at(id));}
     if(isVoid)effect(n,args,candidate,id);else{Value v=valueNode(n,args,read,id);if(isWorld)broadcast=encode(v);else result.map[id]=std::move(v);}
    }});
   if(!isVoid){if(isWorld){mpi::broadcast(world,broadcast,0);result=decode(broadcast);}values[nid]=std::move(result);}
  }
  collectively([&]{validate(candidate,false);});
  if(holdTick>=0&&candidate.at("tick").integer()==holdTick){if(world.rank()==0)publish(output+"/speculative-ready","prepared; not accepted");world.barrier();while(!std::filesystem::exists(output+"/release"))std::this_thread::sleep_for(std::chrono::milliseconds(10));}
  accepted=std::move(candidate);for(auto it=context.localBegin();it!=context.localEnd();++it)(*it)->row=accepted.at("entities").at((*it)->row.at(0).text());
  for(auto it=context.localBegin();it!=context.localEnd();++it){int target=owner((*it)->row);if(target!=world.rank()){repast::RepastProcess::instance()->moveAgent((*it)->id,target);++migrations;}}
  repast::RepastProcess::instance()->synchronizeAgentStatus<Agent,Package,Exchange,Exchange,Exchange>(context,exchange,exchange,exchange);
  accepted.at("entities")=rows();writeAccepted();
 }
 void finish(){
  unsigned long moves=0,requests=0;mpi::reduce(world,migrations,moves,std::plus<unsigned long>(),0);mpi::reduce(world,remoteRequests,requests,std::plus<unsigned long>(),0);
  std::vector<int> counts;mpi::gather(world,int(rows().map.size()),counts,0);
  if(world.rank()==0){Value array=Value::list();for(int n:counts)array.array.emplace_back(n);publish(output+"/execution.canon",encode(Value::dict({{"ranks",Value(world.size())},{"migrations",Value(Integer(moves))},{"remoteRequests",Value(Integer(requests))},{"localCounts",array}})));}
 }
};
int main(int argc,char** argv){
 mpi::environment env(argc,argv);mpi::communicator world;
 try{
  std::map<std::string,std::string> opt;for(int i=1;i<argc;i+=2){require(i+1<argc,"Option value required");opt[argv[i]]=argv[i+1];}
  std::string catalog,bundle,input;
  if(world.rank()==0){catalog=readFile(opt.at("--registry"));bundle=readFile(opt.at("--model"));if(!opt.count("--validate-only"))input=readFile(opt.at("--input"));}
  mpi::broadcast(world,catalog,0);mpi::broadcast(world,bundle,0);mpi::broadcast(world,input,0);
  require(sha256("CatalystSimulation-Registry-1:"+catalog)=="710502049ac1f485589d81eb27482360017ed9d048afb0452694792bf23fc367","Unqualified operation catalog");
  registry=decode(catalog);if(opt.count("--disable-operation"))registry.map.erase(opt.at("--disable-operation"));
  if(opt.count("--validate-only")){compileGraph(decode(bundle));return 0;}
  int steps=std::stoi(opt.at("--steps"));require(steps>=0&&steps<=1000,"Step budget");
  repast::RepastProcess::init("",&world);
  {Probe probe(world,input,bundle,opt.at("--output"),opt.count("--layout")?std::stoi(opt.at("--layout")):0,opt.count("--hold-tick")?std::stoi(opt.at("--hold-tick")):-1);
   if(steps){auto& runner=repast::RepastProcess::instance()->getScheduleRunner();runner.scheduleEvent(1,1,repast::Schedule::FunctorPtr(new repast::MethodFunctor<Probe>(&probe,&Probe::advance)));runner.scheduleStop(steps+0.5);runner.run();}
   probe.finish();}
  repast::RepastProcess::instance()->done();return 0;
 }catch(const std::exception& e){std::cerr<<"rank "<<world.rank()<<": "<<e.what()<<std::endl;world.abort(2);return 2;}
}
