#pragma once
#include <unistd.h>

// One compiled graph and SharedContext per placement incarnation. Only command
// boundaries gather a full checkpoint. Private candidates require acceptance
// acknowledgment before a subsequent advance. The supervisor fsyncs receipts.
template<class Engine>inline void runResident(mpi::communicator& world,Engine& probe,const std::string& directory,const std::string& objects=""){
 bool sharded=!objects.empty();
 std::string sessionBytes;if(world.rank()==0)sessionBytes=readFile(directory+"/session.canon");
 mpi::broadcast(world,sessionBytes,0);Value session=decode(sessionBytes);
 require(session.kind==Value::Map&&session.map.size()==7&&session.at("version").integer()==1,"Resident session schema");
 for(auto key:{"world","group","owner","incarnation"})require(identifier(session.at(key).text()),"Resident identity");
 require(session.at("generation").integer()>0&&session.at("modelDigest").text().size()==64,"Resident placement");
 std::vector<int> processIds;mpi::all_gather(world,int(getpid()),processIds);Value pids=Value::list();for(int pid:processIds)pids.array.emplace_back(pid);
 std::string bytes=sharded?"":probe.checkpoint(),checkpointDigest;
 if(sharded)checkpointDigest=probe.shardedCheckpoint(objects);else if(world.rank()==0)checkpointDigest=sha256(bytes);
 if(world.rank()==0)require((sharded?CasStore(objects).get(checkpointDigest):decode(bytes)).at("modelDigest")==session.at("modelDigest"),"Resident model binding");
 mpi::broadcast(world,checkpointDigest,0);bool awaiting=false;int number=0;Integer acceptedRevision=0;unsigned long advanced=0;
 auto reply=[&](const std::string& state){
  auto population=probe.populationStatistics();
  if(world.rank()==0){auto response=Value::dict({{"version",Value(1)},{"session",session},{"number",Value(number)},
   {"state",Value(state)},{"tick",Value(probe.tick())},{"checkpointDigest",Value(checkpointDigest)},{"awaitingAcceptance",Value(awaiting)},
   {"pids",pids},{"snapshots",Value(Integer(probe.snapshotCount()))},{"graphCompilations",Value(1)},{"restores",Value(1)},{"advancedTicks",Value(Integer(advanced))}});
   if(sharded){response.map["profile"]="checkpoint-1";response.map["shardedSnapshots"]=Value(Integer(probe.shardedSnapshotCount()));response.map["rootEntityRowsGathered"]=Value(0);}
   if(!population.map.empty())response.map["population"]=population;
   publish(directory+"/reply.canon",encode(response));}
 };
 if(world.rank()==0)publish(directory+(sharded?"/candidate-root":"/candidate.canon"),sharded?checkpointDigest:bytes);reply("ready");
 while(true){
  std::string command;
  if(world.rank()==0){
   while(command.empty()){
    auto heartbeat=std::filesystem::path(directory+"/supervisor-heartbeat");
    require(std::filesystem::exists(heartbeat)&&std::filesystem::file_time_type::clock::now()-std::filesystem::last_write_time(heartbeat)<std::chrono::seconds(30),"Resident supervisor lease expired");
    if(std::filesystem::exists(directory+"/command.canon")){
     auto raw=readFile(directory+"/command.canon");auto decoded=decode(raw);
     if(decoded.at("number").integer()>number)command=raw;
    }
    if(command.empty())std::this_thread::sleep_for(std::chrono::milliseconds(10));
   }
  }
  mpi::broadcast(world,command,0);Value request=decode(command);
  require(request.kind==Value::Map&&request.map.size()==10&&request.at("version").integer()==1&&request.at("session")==session,"Resident command identity");
  require(request.at("number").integer()==Integer(number)+1,"Resident command sequence");++number;
  std::string action=request.at("action").text();
  require(request.at("checkpointDigest").text()==checkpointDigest,"Resident input frontier mismatch");
  if(action=="stop"){reply("stopped");break;}
  if(action=="ack"){
   auto revision=request.at("acceptedRevision").integer();require(revision>=acceptedRevision&&revision>0,"Resident acceptance revision");
   acceptedRevision=revision;awaiting=false;reply("acknowledged");continue;
  }
  require(action=="advance"&&!awaiting,"Resident candidate awaits GemStone acceptance");
  require(request.at("fromTick").integer()==probe.tick(),"Resident input tick");
  auto target=request.at("targetTick").integer();require(target>probe.tick()&&target-probe.tick()<=64,"Resident advance budget");
  require(request.at("batch").text()==request.at("inputDigest").text()&&request.at("batch").text().size()==64,"Resident batch identity");
  while(probe.tick()<target){probe.advance();++advanced;}
  if(sharded){checkpointDigest=probe.shardedCheckpoint(objects);if(world.rank()==0)publish(directory+"/candidate-root",checkpointDigest);}
  else{bytes=probe.checkpoint();if(world.rank()==0){checkpointDigest=sha256(bytes);publish(directory+"/candidate.canon",bytes);}}
  mpi::broadcast(world,checkpointDigest,0);awaiting=true;reply("candidate");
 }
}
