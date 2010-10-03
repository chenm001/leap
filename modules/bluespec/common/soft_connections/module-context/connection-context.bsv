
// ****** Connection Context Support Functions ******

// These are Bluespec modules just to work with ModuleContext.
// By most definitions they should be thought of as functions.

// Modules with empty interfaces are like C++ functions that return
// void. They only have a side effect on the context.

// Otherwise the "interface" of the module is actually the return
// type of the function.


// freshContext

// An empty context. Usually passed as a parameter to runWithContext().


LOGICAL_CONNECTION_INFO freshContext = LOGICAL_CONNECTION_INFO 
                                       {
                                          unmatchedSends: tagged Nil,
                                          unmatchedRecvs: tagged Nil,
                                          chains: Vector::replicate(tagged Nil),
                                          stations: tagged Nil,
                                          stationStack: tagged Nil,
                                          rootStationName: "InvalidRootStation",
                                          softReset: ? // Be aware this will fail if accessed by user code.
                                       };


// resetContext

// Reset the context. This is more useful because the softReset = ? can cause 
// the Bluespec compiler to errror out if accessed.

module [ConnectedModule] resetContext ();

  LOGICAL_CONNECTION_INFO ctx;
  
  ctx.unmatchedSends = tagged Nil;
  ctx.unmatchedRecvs = tagged Nil;
  ctx.chains = Vector::replicate(tagged Nil);
  ctx.stations = tagged Nil;
  ctx.stationStack = tagged Nil;
  ctx.rootStationName = "InvalidRootStation";
  putContext(freshContext);
  Reset cur_reset <- exposeCurrentReset();
  putSoftReset(cur_reset);

endmodule




// ****** Accessors ******

// These just access the specified field.

module [ConnectedModule] getUnmatchedSends (List#(LOGICAL_SEND_INFO));

   let ctxt <- getContext();
   return ctxt.unmatchedSends;

endmodule

module [ConnectedModule] getUnmatchedRecvs (List#(LOGICAL_RECV_INFO));

   let ctxt <- getContext();
   return ctxt.unmatchedRecvs;

endmodule

module [ConnectedModule] getStationInfos (List#(STATION_INFO));

    let ctxt <- getContext();
    return ctxt.stations;

endmodule

module [ConnectedModule] getStationStack (List#(STATION));

    let ctxt <- getContext();
    return ctxt.stationStack;

endmodule

module [ConnectedModule] getRootStationName (String);

    let ctxt <- getContext();
    return ctxt.rootStationName;

endmodule

module [ConnectedModule] getSoftReset (Reset);

    let ctxt <- getContext();
    return ctxt.softReset;

endmodule

// BACKWARDS COMPATABILITY: Connection Chains

module [ConnectedModule] getChain#(Integer idx) (List#(LOGICAL_CHAIN_INFO));

    let ctxt <- getContext();
    return ctxt.chains[idx];

endmodule

// ****** Mutators *******

// These update the field to the given value.

// putUnmatchedSends

module [ConnectedModule] putUnmatchedSends#(List#(LOGICAL_SEND_INFO) new_sends) ();

    let ctxt <- getContext();
    ctxt.unmatchedSends = new_sends;
    putContext(ctxt);

endmodule


// putUnmatchedRecvs

module [ConnectedModule] putUnmatchedRecvs#(List#(LOGICAL_RECV_INFO) new_recvs) ();

    let ctxt <- getContext();
    ctxt.unmatchedRecvs = new_recvs;
    putContext(ctxt);

endmodule

// putStations

module [ConnectedModule] putStationInfos#(List#(STATION_INFO) new_stations) ();

    let ctxt <- getContext();
    ctxt.stations = new_stations;
    putContext(ctxt);

endmodule

// putStationStack

module [ConnectedModule] putStationStack#(List#(STATION) new_stations) ();

    let ctxt <- getContext();
    ctxt.stationStack = new_stations;
    putContext(ctxt);

endmodule

// putRootStationName

module [ConnectedModule] putRootStationName#(String new_root) ();

    let ctxt <- getContext();
    ctxt.rootStationName = new_root;
    putContext(ctxt);

endmodule

// putSoftReset

module [ConnectedModule] putSoftReset#(Reset new_reset) ();

    let ctxt <- getContext();
    ctxt.softReset = new_reset;
    putContext(ctxt);

endmodule

// putChain

module [ConnectedModule] putChain#(Integer idx, List#(LOGICAL_CHAIN_INFO) chain) ();

    let ctxt <- getContext();
    ctxt.chains[idx] = chain;
    putContext(ctxt);

endmodule

// ****** Non-Primitive Mutators ******


// addUnmatchedSend/Recv

// Add a new send/recv to the list.

module [ConnectedModule] addUnmatchedSend#(LOGICAL_SEND_INFO new_send) ();

   let sends <- getUnmatchedSends();
   putUnmatchedSends(List::cons(new_send, sends));

endmodule

module [ConnectedModule] addUnmatchedRecv#(LOGICAL_RECV_INFO new_recv) ();

   let recvs <- getUnmatchedRecvs();
   putUnmatchedRecvs(List::cons(new_recv, recvs));

endmodule

// removeUnmatchedSend/Recv

// Remove an unmatched send/recv (usually because it's been matched). 

module [ConnectedModule] removeUnmatchedSend#(String sname) ();

  let sends <- getUnmatchedSends();
  let new_sends = List::filter(sendNameDoesNotMatch(sname), sends);
  putUnmatchedSends(new_sends);

endmodule

module [ConnectedModule] removeUnmatchedRecv#(String rname) ();

  let recvs <- getUnmatchedRecvs();
  let new_recvs = List::filter(recvNameDoesNotMatch(rname), recvs);
  putUnmatchedRecvs(new_recvs);

endmodule

// findStationInfo

// Find the info associated with a a station name (or error).

module [ConnectedModule] findStationInfo#(String station_name) (STATION_INFO);

  List#(STATION_INFO) st_infos <- getStationInfos();
  
  Bool found = False;
  STATION_INFO res = ?;

  while (!List::isNull(st_infos) && !found)
  begin
      STATION_INFO cur = List::head(st_infos);
      if (cur.stationName == station_name)
      begin
          found = True;
          res = cur;
      end
      st_infos = List::tail(st_infos);
  end

  if (found)
    return res;
  else
    return error("Could not find a Station named " + station_name);

endmodule

// updateStationInfo

// Update a given station's info to the new values.

module [ConnectedModule] updateStationInfo#(String station_name, STATION_INFO new_info) ();

  List#(STATION_INFO) st_infos <- getStationInfos();
  List#(STATION_INFO) new_infos = List::nil;
  Bool found = False;

  while (!found && !List::isNull(st_infos))
  begin
      STATION_INFO cur = List::head(st_infos);
      if (cur.stationName == station_name)
      begin
          new_infos = List::append(List::tail(st_infos), List::cons(new_info, new_infos));
          found = True;
      end
      else
      begin
          new_infos = List::cons(cur, new_infos);
      end
      st_infos = List::tail(st_infos);
  end
  
  if (found)
      putStationInfos(new_infos);
  else
      return error("Could not find a Station named " + station_name);

endmodule

// We arrange logical stations into a stack.
// These functions manipulate the stack.

module [ConnectedModule] pushStation#(STATION s) ();

    let ss <- getStationStack();
    putStationStack(List::cons(s,ss));

endmodule

module [ConnectedModule] popStation ();

    let ss <- getStationStack();
    case (ss) matches
        tagged Nil:
        begin
            error("popStation() called on empty station stack.");
        end
        default:
        begin
            putStationStack(List::tail(ss));
        end
    endcase

endmodule

module [ConnectedModule] getCurrentStation (STATION);

    let ss <- getStationStack();
    return case (ss) matches
               tagged Nil:
               begin
                   return error("getCurrentStation() called on empty station stack.");
               end
               default:
               begin
                   return (List::head(ss));
               end
           endcase;

endmodule

module [ConnectedModule] getCurrentStationM (Maybe#(STATION));

    let ss <- getStationStack();
    return case (ss) matches
               tagged Nil:
               begin
                   return tagged Invalid;
               end
               default:
               begin
                   return tagged Valid (List::head(ss));
               end
           endcase;

endmodule

// getMulticast{Send/Recvs}

// get all multicast send/recvs and remove them from the list.

module [ConnectedModule] getMulticastSends (List#(LOGICAL_SEND_INFO));

  let sends <- getUnmatchedSends();
  let result = List::filter(sendIsOneToMany, sends);
  let remaining_sends = List::filter(sendIsNotOneToMany, sends); 
  putUnmatchedSends(remaining_sends);
  
  return result;

endmodule


module [ConnectedModule] getMulticastRecvs (List#(LOGICAL_RECV_INFO));

  let recvs <- getUnmatchedRecvs();
  let result = List::filter(recvIsManyToOne, recvs);
  let remaining_recvs = List::filter(recvIsNotManyToOne, recvs); 
  putUnmatchedRecvs(remaining_recvs);
  
  return result;

endmodule
