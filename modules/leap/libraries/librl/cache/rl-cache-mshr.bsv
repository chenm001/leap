//
// Copyright (C) 2013 MIT
//
// This program is free software; you can redistribute it and/or
// modify it under the terms of the GNU General Public License
// as published by the Free Software Foundation; either version 2
// of the License, or (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program; if not, write to the Free Software
// Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
//

//
// Cache Miss Status Handling Registers (MSHR)
//

// Library imports.

import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import FIFOLevel :: * ;

// Project foundation imports.

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/fpga_components.bsh"

// ===================================================================
//
// PUBLIC DATA STRUCTURES
//
// ===================================================================

//
// MSHR local response (to update cache)
//
typedef struct
{
    t_CACHE_ADDR              addr;
    t_CACHE_WORD              val;
    RL_COH_DM_CACHE_COH_STATE newState;
    Bool                      isCacheable;
    RL_COH_CACHE_REQ_TYPE     msgType;
    t_CACHE_CLIENT_META       clientMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_COH_DM_CACHE_MSHR_LOCAL_RESP#(type t_CACHE_ADDR,
                                 type t_CACHE_WORD,
                                 type t_CACHE_CLIENT_META)
    deriving (Eq, Bits);

//
// MSHR remote response (to write back or serve other caches)
//
typedef struct
{
    t_NW_REQ_IDX  reqIdx;
    t_CACHE_WORD  val;
    Bool          retry;       // ask GETX requestor to retry
    Bool          nullResp;
}
RL_COH_DM_CACHE_MSHR_REMOTE_RESP#(type t_NW_REQ_IDX,
                                  type t_CACHE_WORD)
    deriving (Eq, Bits);


//
// Miss status handling register (MSHR) interface for coherent caches
//
// t_CACHE_CLIENT_META is the client's metadata and is stored in the MSHR
// t_NW_REQ_IDX is the index of the completion table allocated in the 
// cache's router (CACHE_SOURCE_DATA)
//
interface RL_COH_DM_CACHE_MSHR#(type t_CACHE_ADDR,
                                type t_CACHE_WORD,
                                type t_CACHE_MASK,
                                type t_CACHE_CLIENT_META,
                                type t_MSHR_IDX,
                                type t_NW_REQ_IDX);
    //
    // Requests that need to allocate a new MSHR entry (triggered by local requests) 
    //
    // Request for share data
    method Action getShare(t_MSHR_IDX idx,
                           t_CACHE_ADDR addr,
                           t_CACHE_CLIENT_META meta);
    
    // Request for data and exlusive ownership
    method Action getExclusive(t_MSHR_IDX idx,
                               t_CACHE_ADDR addr,
                               t_CACHE_WORD val,
                               t_CACHE_WORD writeData,
                               t_CACHE_MASK byteWriteMask, 
                               RL_COH_DM_CACHE_COH_STATE oldState);

    // Write back and give up ownership
    method Action putExclusive(t_MSHR_IDX idx,
                               t_CACHE_ADDR addr, 
                               t_CACHE_WORD val,
                               Bool needResp,
                               Bool isCleanWB);
    
    // Pass invalidate and flush requests down the hierarchy.
    // method Action invalReq(t_CACHE_ADDR addr);
    // method Action flushReq(t_CACHE_ADDR addr);
   
    // Check if there is an available MSHR entry to handle a new miss
    method Bool entryAvailable(t_MSHR_IDX idx);

    // Return true if there is an MSHR entry released
    method Bool entryReleased();

    // Activated requests from the network
    method Action activatedReq(t_MSHR_IDX mshrIdx,
                               t_CACHE_ADDR addr,
                               Bool ownReq,
                               t_NW_REQ_IDX reqIdx,
                               RL_COH_CACHE_REQ_TYPE reqType);

    // Responses received from the network
    method Action recvResp(RL_COH_DM_CACHE_FILL_RESP#(t_CACHE_WORD, t_MSHR_IDX) resp);
    
    // Return true if data response queue (from network) is almost full
    method Bool dataRespQAlmostFull();
    
    // Local responses to cache 
    method ActionValue#(RL_COH_DM_CACHE_MSHR_LOCAL_RESP#(t_CACHE_ADDR, 
                                                         t_CACHE_WORD,
                                                         t_CACHE_CLIENT_META)) localResp();
    // Remote responses to network
    method ActionValue#(RL_COH_DM_CACHE_MSHR_REMOTE_RESP#(t_NW_REQ_IDX,
                                                          t_CACHE_WORD)) remoteResp();
    // Retry request to network
    method ActionValue#(Tuple2#(t_CACHE_ADDR, t_MSHR_IDX)) retryReq();
    
    // Return true if a read request has been processed (received activated GETS req)
    method Bool getShareProcessed();
    // Return true if a write request has been processed (received response for GETX)
    method Bool getExclusiveProcessed();
    // Return true if there is at least one pending read request
    method Bool getSharePending();
    // Return true if there is at least one pending write request
    method Bool getExclusivePending();
    
endinterface: RL_COH_DM_CACHE_MSHR


// ===================================================================
//
// Internal types
//
// ===================================================================

//
// Cache transient states for coherent caches (MOSI)
// 
// We support automatic transition from S to M by letting the lower level memory
// give out the data ownership to the first GETS request. 
// 
// If the cache receives a GETS response with ownership, it automatically upgrades
// the cache state to COH_DM_CACHE_STATE_M (instead of COH_DM_CACHE_STATE_S).
// If the response does not include ownership, the cache state will only 
// changed from COH_DM_CACHE_STATE_I to COH_DM_CACHE_STATE_S.
// 
// To simplify the state transition in the MSHR, we merge the transition state
// COH_CACHE_STATE_IS_AD with COH_CACHE_STATE_IM_AD, COH_CACHE_STATE_IS_D with 
// COH_CACHE_STATE_IM_D, COH_CACHE_STATE_IS_D_I with COH_CACHE_STATE_IM_D_I.
// MSHR has a field called isRead to indicate whether the entry is allocated 
// by GETS or GETX.
//
typedef enum
{
    COH_CACHE_STATE_IM_AD,   // invalid (or shared), issued GETS/GETX, have not seen GETS/GETX or data yet
    COH_CACHE_STATE_OM_A,    // owned, issued GETX, have not seen GETX yet

    COH_CACHE_STATE_IS_A,    // invalid, issued GETS, have not seen GETS, have seen data without ownership
    COH_CACHE_STATE_IM_A,    // invalid (or shared), issued GETS/GETX, have not seen GETX, have seen data with ownership

    COH_CACHE_STATE_IM_D,    // invalid (or shared), issued GETS/GETX, have seen GETS/GETX, have not seen data yet
    COH_CACHE_STATE_IM_D_O,  // invalid (or shared), issued GETS/GETX, have seen GETS/GETX, have not seen data yet, then saw other GETS
    COH_CACHE_STATE_IM_D_I,  // invalid (or shared), issued GETS/GETX, have seen GETS/GETX, have not seen data yet, then saw other GETX
    COH_CACHE_STATE_IM_D_OI  // invalid (or shared), issued GETS/GETX, have seen GETS/GETX, have not seen data yet, then saw other GETS, then saw other GETX
}
RL_COH_CACHE_TRANS_STATE
    deriving (Eq, Bits);


// MSHR entry for GETX/GETS
typedef struct
{
    t_MSHR_ADDR               addr;
    t_MSHR_WORD               val;
    t_MSHR_WORD               writeData;
    t_MSHR_MASK               byteWriteMask;
    RL_COH_CACHE_TRANS_STATE  state;
    Bool                      isRead;
    Bool                      isCacheable; // GETS can be non-cacheable
    Bool                      doubleReqs;
    t_CLIENT_META             meta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
    Vector#(n_ENTRIES, Bool)  forwardMeta;
}
RL_COH_DM_CACHE_MSHR_GET_ENTRY#(type t_MSHR_ADDR, 
                                type t_MSHR_WORD,
                                type t_MSHR_MASK,
                                type t_CLIENT_META,
                                numeric type n_ENTRIES)
    deriving (Eq, Bits);

// MSHR entry for PUTX
typedef struct
{
    t_MSHR_ADDR              addr;
    t_MSHR_WORD              val;
    Bool                     needResp;    // PUTX caused by read/write misses does not need response
    Bool                     isCleanWB;
}
RL_COH_DM_CACHE_MSHR_PUT_ENTRY#(type t_MSHR_ADDR, 
                                type t_MSHR_WORD)
    deriving (Eq, Bits);


// MSHR Get request 
typedef struct
{
    t_MSHR_IDX                idx;
    t_MSHR_ADDR               addr;
    t_MSHR_WORD               val;
    t_MSHR_WORD               writeData;
    t_MSHR_MASK               byteWriteMask;
    RL_COH_CACHE_TRANS_STATE  state;
    t_CLIENT_META             meta;
    Bool                      isGetX;
}
RL_COH_DM_CACHE_MSHR_GET_REQ#(type t_MSHR_IDX,
                              type t_MSHR_ADDR, 
                              type t_MSHR_WORD,
                              type t_MSHR_MASK,
                              type t_CLIENT_META)
    deriving (Eq, Bits);

// MSHR Put request 
typedef struct
{
    t_MSHR_IDX                idx;
    t_MSHR_ADDR               addr;
    t_MSHR_WORD               val;
    Bool                      needResp;
    Bool                      isCleanWB;
}
RL_COH_DM_CACHE_MSHR_PUT_REQ#(type t_MSHR_IDX,
                              type t_MSHR_ADDR, 
                              type t_MSHR_WORD)
    deriving (Eq, Bits);
    
// ===================================================================
//
// MSHR implementation
//
// ===================================================================

//
// mkMSHRForDirectMappedCache --
//   
//
module [m] mkMSHRForDirectMappedCache#(DEBUG_FILE debugLog)
    // interface:
    (RL_COH_DM_CACHE_MSHR#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_CLIENT_META, t_MSHR_IDX, t_NW_REQ_IDX))
    //
    provisos (IsModule#(m, m__),
              Bits#(t_CACHE_ADDR, t_CACHE_ADDR_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),
              Bits#(t_CACHE_MASK, t_CACHE_MASK_SZ),
              Bits#(t_CACHE_CLIENT_META, t_CACHE_CLIENT_META_SZ),
              Bits#(t_MSHR_IDX, t_MSHR_IDX_SZ),
              Bits#(t_NW_REQ_IDX, t_NW_REQ_IDX_SZ),
              Div#(t_CACHE_WORD_SZ, 8, t_CACHE_MASK_SZ),
              Alias#(RL_COH_DM_CACHE_FILL_RESP#(t_CACHE_WORD, t_MSHR_IDX), t_CACHE_FILL_RESP),
              Alias#(RL_COH_DM_CACHE_MSHR_REMOTE_RESP#(t_NW_REQ_IDX, t_CACHE_WORD), t_REMOTE_RESP),
              Alias#(RL_COH_DM_CACHE_MSHR_LOCAL_RESP#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_CLIENT_META), t_LOCAL_RESP),
              Alias#(RL_COH_DM_CACHE_MSHR_GET_ENTRY#(t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_CLIENT_META, TExp#(t_NW_REQ_IDX_SZ)), t_MSHR_GET_ENTRY),
              Alias#(RL_COH_DM_CACHE_MSHR_PUT_ENTRY#(t_CACHE_ADDR, t_CACHE_WORD), t_MSHR_PUT_ENTRY),
              Alias#(RL_COH_DM_CACHE_MSHR_GET_REQ#(t_MSHR_IDX, t_CACHE_ADDR, t_CACHE_WORD, t_CACHE_MASK, t_CACHE_CLIENT_META), t_MSHR_GET_REQ),
              Alias#(RL_COH_DM_CACHE_MSHR_PUT_REQ#(t_MSHR_IDX, t_CACHE_ADDR, t_CACHE_WORD), t_MSHR_PUT_REQ),
              Bounded#(t_MSHR_IDX));

    LUTRAM#(t_MSHR_IDX, t_MSHR_GET_ENTRY) mshrGet <- mkLUTRAMU();
    LUTRAM#(t_MSHR_IDX, t_MSHR_PUT_ENTRY) mshrPut <- mkLUTRAMU();
    LUTRAM#(t_MSHR_IDX, Bool) mshrGetValidBits <- mkLUTRAM(False);
    LUTRAM#(t_MSHR_IDX, Bool) mshrPutValidBits <- mkLUTRAM(False);

    Wire#(Tuple4#(t_MSHR_IDX, Bool, t_NW_REQ_IDX, RL_COH_CACHE_REQ_TYPE)) curActivatedReq <- mkWire();
    
    RWire#(t_MSHR_GET_ENTRY)  curGetEntry                 <- mkRWire();
    RWire#(t_MSHR_PUT_ENTRY)  curPutEntry                 <- mkRWire();
    FIFOF#(t_REMOTE_RESP)     respToNetworkQ              <- mkFIFOF();
    FIFOF#(t_LOCAL_RESP)      respLocalQ                  <- mkFIFOF();
    FIFOF#(t_CACHE_FILL_RESP) respFromNetworkQ            <- mkSizedFIFOF(8);
    FIFOF#(Tuple2#(t_CACHE_ADDR, t_MSHR_IDX)) retryReqQ   <- mkFIFOF();
    FIFOF#(t_MSHR_GET_REQ)    getReqQ                     <- mkBypassFIFOF();
    FIFOF#(t_MSHR_PUT_REQ)    putReqQ                     <- mkBypassFIFOF();
    FIFOF#(t_MSHR_IDX)        resendGetxQ                 <- mkSizedFIFOF(valueOf(TExp#(t_MSHR_IDX_SZ)));                

    COUNTER#(3) numBufferedResps <- mkLCounter(0);
    Reg#(Bool) respAlmostFull    <- mkReg(False);

    Wire#(Bool) curGetBusy       <- mkWire();
    Wire#(Bool) curPutBusy       <- mkWire();

    PulseWire mshrReleaseW       <- mkPulseWire();
    PulseWire activatedReqEnW    <- mkPulseWire();
    PulseWire cacheGetReqEnW     <- mkPulseWire();
    PulseWire cachePutReqEnW     <- mkPulseWire();
    PulseWire mshrGetAllocateW   <- mkPulseWire();
    PulseWire resendGetxW        <- mkPulseWire();

    //track inflight GETX/GETS requests
    PulseWire getsProcessedW                          <- mkPulseWire();
    PulseWire getxProcessedW                          <- mkPulseWire();
    COUNTER#((TAdd#(t_MSHR_IDX_SZ,1))) numPendingGetX <- mkLCounter(0);
    COUNTER#((TAdd#(t_MSHR_IDX_SZ,1))) numPendingGetS <- mkLCounter(0);

    //
    // Because forwarding data to multiple caches take multiple cycles,
    // mark mshr to be busy and block requests from the cache when processing multi-forwarding operations
    // 
    Reg#(Bool) mshrBusy             <- mkReg(False);
    Reg#(t_MSHR_IDX) mshrBusyIdx    <- mkReg(unpack(0));
    Reg#(Bool) fwdNullResp          <- mkReg(False);

    //
    // Apply write mask and return the updated data
    //
    function t_CACHE_WORD applyWriteMask(t_CACHE_WORD oldVal, t_CACHE_WORD wData, t_CACHE_MASK mask);
        Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_out = newVector();
        Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_old = unpack(resize(pack(oldVal)));
        Vector#(t_CACHE_MASK_SZ, Bit#(8)) bytes_new = unpack(resize(pack(wData)));
        Vector#(t_CACHE_MASK_SZ, Bool) mask_v       = unpack(pack(mask));
        for (Integer b = 0; b < valueOf(t_CACHE_MASK_SZ); b = b + 1)
        begin
            bytes_out[b] = mask_v[b] ? bytes_new[b] : bytes_old[b];
        end
        return unpack(resize(pack(bytes_out))); 
    endfunction


    (* fire_when_enabled *)
    rule updateRespReg (True);
        let n = numBufferedResps.value;
        if (respAlmostFull && n < 3)
        begin
            respAlmostFull <= False;
        end
        else if (!respAlmostFull && n > 6)
        begin
            respAlmostFull <= True;
        end
    endrule

    // allocate MSHR entry for GETS/GETX
    rule allocateGetMshr (!mshrBusy);
        let r = getReqQ.first();
        getReqQ.deq();
        
        debugLog.record($format("        MSHR: allocate new entry (0x%x) for %s request (addr=0x%x)", 
                        r.idx, (r.isGetX)? "GETX" : "GETS", r.addr));
        
        mshrGetAllocateW.send();
        mshrGet.upd(r.idx, RL_COH_DM_CACHE_MSHR_GET_ENTRY{ addr: r.addr,
                                                           val: r.val,
                                                           writeData: r.writeData,
                                                           byteWriteMask: r.byteWriteMask,
                                                           state: r.state,
                                                           isRead: !r.isGetX,
                                                           isCacheable: (r.state == COH_CACHE_STATE_OM_A),
                                                           doubleReqs: False,
                                                           meta: r.meta,
                                                           globalReadMeta: ?,
                                                           forwardMeta: replicate(False)});

    endrule
    
    // allocate MSHR entry for PUTX
    rule allocatePutMshr (!mshrBusy);
        let r = putReqQ.first();
        putReqQ.deq();
        debugLog.record($format("        MSHR: allocate new entry (0x%x) for PUTX request (addr=0x%x), isCleanWB=%s", 
                        r.idx, r.addr, r.isCleanWB? "True" : "False"));
        
        mshrPut.upd(r.idx, RL_COH_DM_CACHE_MSHR_PUT_ENTRY{ addr: r.addr,
                                                           val: r.val,
                                                           needResp: r.needResp,
                                                           isCleanWB: r.isCleanWB });
    endrule

    // receive own activated GETS/GETX request
    rule ownGetMshrHit (curGetEntry.wget() matches tagged Valid .e &&& tpl_2(curActivatedReq));
        
        match { .mshr_idx, .own_req, .req_idx, .req_type } = curActivatedReq;
        
        debugLog.record($format("        MSHR: own GET request on entry=0x%x, addr=0x%x, val=0x%x, state=%d, meta=0x%x", mshr_idx, e.addr, e.val, e.state, e.meta));
        
        let new_entry     = e;
        Bool mshr_release = False;
        t_LOCAL_RESP resp = RL_COH_DM_CACHE_MSHR_LOCAL_RESP { addr: e.addr,
                                                              val: e.val,
                                                              newState: ?,
                                                              isCacheable: e.isCacheable,
                                                              msgType: (e.isRead)? COH_CACHE_GETS : COH_CACHE_GETX,
                                                              clientMeta: e.meta,
                                                              globalReadMeta: e.globalReadMeta };

        if (e.isRead)
        begin
            getsProcessedW.send();
            numPendingGetS.down();
            debugLog.record($format("        MSHR: receive activated GETS, numPendingGetS=%x", numPendingGetS.value()));
        end
        
        case (e.state)
            COH_CACHE_STATE_IM_AD:
            begin
                if (e.doubleReqs) // ignore the first activated request (this request is already retried)
                begin
                    new_entry.doubleReqs = False;
                end
                else
                begin
                    new_entry.state = COH_CACHE_STATE_IM_D;
                end
            end
            COH_CACHE_STATE_IS_A:
            begin
                mshr_release   = True;
                resp.newState  = COH_DM_CACHE_STATE_S;
            end
            COH_CACHE_STATE_OM_A, COH_CACHE_STATE_IM_A:
            begin
                if (e.doubleReqs) // ignore the first activated request (this request is already retried)
                begin
                    new_entry.doubleReqs = False;
                end
                else
                begin
                    mshr_release   = True;
                    resp.newState  = COH_DM_CACHE_STATE_M;
                    resp.val       = applyWriteMask(e.val, e.writeData, e.byteWriteMask);
                end
            end
        endcase

        if (!mshr_release)
        begin
            mshrGet.upd(mshr_idx, new_entry);
            debugLog.record($format("        MSHR: mshrGet entry (0x%x) update: val=0x%x, state=%d", mshr_idx, new_entry.val, new_entry.state));
        end
        else // release mshrGet entry
        begin
            if (e.state == COH_CACHE_STATE_OM_A)
            begin
                getxProcessedW.send();
                numPendingGetX.down();
                debugLog.record($format("        MSHR: GETX entry release, numPendingGetX=%x", numPendingGetX.value()));
            end

            debugLog.record($format("        MSHR: mshrGet entry (0x%x) release", mshr_idx));
            mshrGetValidBits.upd(mshr_idx, False);
            if (!curPutBusy)
            begin
                mshrReleaseW.send();
            end
            //send response to cache
            respLocalQ.enq(resp);
            debugLog.record($format("        MSHR: localResp: addr=0x%x, val=0x%x, state=%d, msgType=%s", 
                            resp.addr, resp.val, resp.newState, (e.isRead)? "GETS": "GETX"));
        end

    endrule

    // receive own activated PUTX request
    rule ownPutMshrHit (curPutEntry.wget() matches tagged Valid .e &&& tpl_2(curActivatedReq));
        
        match { .mshr_idx, .own_req, .req_idx, .req_type } = curActivatedReq;
        
        debugLog.record($format("        MSHR: own PUT request on entry=0x%x, addr=0x%x, val=0x%x, isCleanWB=%s", 
                        mshr_idx, e.addr, e.val, e.isCleanWB? "True" : "False"));
        
        // send local response back to cache
        respLocalQ.enq( RL_COH_DM_CACHE_MSHR_LOCAL_RESP { addr: e.addr,
                                                          val: e.val,
                                                          newState: COH_DM_CACHE_STATE_I,
                                                          isCacheable: e.needResp,
                                                          msgType: COH_CACHE_PUTX,
                                                          clientMeta: ?,
                                                          globalReadMeta: ? } );
        debugLog.record($format("        MSHR: localResp: addr=0x%x, val=0x%x, state=%d, isCacheable=%s", 
                        e.addr, e.val, COH_DM_CACHE_STATE_I, e.needResp? "True" : "False"));
        
        // release mshrPut entry
        mshrPutValidBits.upd(mshr_idx, False);
        debugLog.record($format("        MSHR: mshrPut entry (0x%x) release", mshr_idx));
        if (!curGetBusy)
        begin
            mshrReleaseW.send();
        end
       
        if (!e.isCleanWB)
        begin
            // send write back data to network if it's not clean write-back
            respToNetworkQ.enq( RL_COH_DM_CACHE_MSHR_REMOTE_RESP { reqIdx: req_idx,
                                                                   val: e.val,
                                                                   retry: False,
                                                                   nullResp: False } );
            
            debugLog.record($format("        MSHR: remoteResp: reqIdx=0x%x, val=0x%x, retry=%s, nullResp=%s", 
                                    req_idx, e.val, "False", "False"));
        end
    endrule

    (* descending_urgency = "ownGetMshrHit, otherGetMshrHit, allocateGetMshr" *)
    // receive other activated GETS/GETX request on mshrGet entry
    // other activated PUTX are ignored 
    (*fire_when_enabled*)
    rule otherGetMshrHit (curGetEntry.wget() matches tagged Valid .e &&& !tpl_2(curActivatedReq));
        
        match { .mshr_idx, .own_req, .req_idx, .req_type } = curActivatedReq;
        
        debugLog.record($format("        MSHR: other GET request on entry=0x%x, addr=0x%x, val=0x%x, state=%d", mshr_idx, e.addr, e.val, e.state));
        
        Bool resp_delay = False;

        t_REMOTE_RESP resp = RL_COH_DM_CACHE_MSHR_REMOTE_RESP { reqIdx: req_idx,
                                                                val: e.val,
                                                                retry: False,
                                                                nullResp: True };
        let new_entry = e;

        case (e.state)
            COH_CACHE_STATE_OM_A:
            begin
                new_entry.state = (req_type == COH_CACHE_GETX)? COH_CACHE_STATE_IM_AD : e.state;
                resp.nullResp = False;
            end
            COH_CACHE_STATE_IM_D:
            begin
                new_entry.state = (req_type == COH_CACHE_GETX)? COH_CACHE_STATE_IM_D_I : COH_CACHE_STATE_IM_D_O;
                resp_delay = True;
                new_entry.forwardMeta[pack(req_idx)] = True;
            end
            COH_CACHE_STATE_IM_D_O:
            begin
                new_entry.state = (req_type == COH_CACHE_GETX)? COH_CACHE_STATE_IM_D_OI : e.state;
                resp_delay = True;
                new_entry.forwardMeta[pack(req_idx)] = True;
            end 
        endcase

        // update mshr
        mshrGet.upd(mshr_idx, new_entry);
        debugLog.record($format("        MSHR: mshrGet entry (0x%x) update: val=0x%x, state=%d", mshr_idx, new_entry.val, new_entry.state));

        // send response to network if not delayed
        if (!resp_delay)
        begin
            respToNetworkQ.enq(resp);
            debugLog.record($format("        MSHR: remoteResp: reqIdx=0x%x, val=0x%x, retry=%s, nullResp=%s", 
                                    resp.reqIdx, resp.val, (resp.retry)? "True" : "False", (resp.nullResp)? "True": "False"));
        end

    endrule

    (* descending_urgency = "ownPutMshrHit, otherPutMshrHit, allocatePutMshr" *)
    // receive other activated GETS/GETX request on mshrPut entry
    // other activated PUTX are ignored 
    (*fire_when_enabled*)
    rule otherPutMshrHit (curPutEntry.wget() matches tagged Valid .e &&& !tpl_2(curActivatedReq));
        
        let resp = RL_COH_DM_CACHE_MSHR_REMOTE_RESP { reqIdx: tpl_3(curActivatedReq),
                                                      val: e.val,
                                                      retry: (tpl_4(curActivatedReq) == COH_CACHE_GETX),
                                                      nullResp: False };
        respToNetworkQ.enq(resp);

        debugLog.record($format("        MSHR: remoteResp: reqIdx=0x%x, val=0x%x, retry=%s, nullResp=%s", 
                                resp.reqIdx, resp.val, (resp.retry)? "True" : "False", (resp.nullResp)? "True": "False"));
    endrule

    // receive other activated GETS/GETX request which misses in both mshrGet and mshrPut
    // send null response to network
    (*fire_when_enabled*)
    rule otherMshrMiss (!isValid(curPutEntry.wget()) && !isValid(curGetEntry.wget()) && !tpl_2(curActivatedReq));
        respToNetworkQ.enq( RL_COH_DM_CACHE_MSHR_REMOTE_RESP { reqIdx: tpl_3(curActivatedReq),
                                                               val: ?,
                                                               retry: ?,
                                                               nullResp: True } );
        debugLog.record($format("        MSHR: MISS remoteResp: nullResp=True")); 
    endrule

    (* mutually_exclusive = "mshrForward, processRespFromNetwork, resendGetX, ownPutMshrHit, ownGetMshrHit, otherGetMshrHit, otherPutMshrHit, otherMshrMiss" *)
    // process responses received from network
    rule processRespFromNetwork (!activatedReqEnW && !cacheGetReqEnW && !cachePutReqEnW && !mshrGetAllocateW && !resendGetxW && !mshrBusy);
        let r = respFromNetworkQ.first();
        respFromNetworkQ.deq();
        numBufferedResps.down();
        let e = mshrGet.sub(r.meta);
        let new_entry = e;

        if (r.retry) // response that asks mshr to resend GETX
        begin
            debugLog.record($format("        MSHR: retry on entry=0x%x, addr=0x%x, state=%d", r.meta, e.addr, e.state));
            // if the mshr has not seen its own activated GETX (still in COH_CACHE_STATE_IM_AD state)
            // marks the doubleReqs field so that it will skip its first coming activated GETX in the future
            new_entry.doubleReqs = (e.state == COH_CACHE_STATE_IM_AD);
            
            // reset mshr entry
            new_entry.state = COH_CACHE_STATE_IM_AD;
            new_entry.forwardMeta = replicate(False);
            mshrGet.upd(r.meta, new_entry);
            debugLog.record($format("        MSHR: mshrGet entry (0x%x) update: state=%d, doubleReqs=%s", r.meta, e.addr, (new_entry.doubleReqs)? "True" : "False"));
            
            // send retry request
            if (retryReqQ.notFull())
            begin
                retryReqQ.enq(tuple2(e.addr, r.meta));
                debugLog.record($format("        MSHR: resend GETX req: addr=0x%x, entry=0x%x", e.addr, r.meta));
            end
            else
            begin
                resendGetxQ.enq(r.meta);
                debugLog.record($format("        MSHR: resend GETX req queue is full, wait in the resendGetxQ: addr=0x%x, entry=0x%x", e.addr, r.meta));
            end
        end
        else // normal data responses
        begin
            debugLog.record($format("        MSHR: response on entry=0x%x, addr=0x%x, val=0x%x, state=%d, meta=0x%x", r.meta, e.addr, e.val, e.state, e.meta));
            
            if (!e.isRead)
            begin
                getxProcessedW.send();
                numPendingGetX.down();
                debugLog.record($format("        MSHR: GETX entry release, numPendingGetX=%x", numPendingGetX.value()));
            end

            let mshr_release        = False;
            let mshr_delay          = False;
            let send_remote_resp    = False;
            let new_val             = ?;
            let forward_idx         = ?;
            t_LOCAL_RESP local_resp = RL_COH_DM_CACHE_MSHR_LOCAL_RESP { addr: e.addr,
                                                                        val: r.val,
                                                                        newState: ?,
                                                                        isCacheable: r.isCacheable,
                                                                        msgType: (e.isRead)? COH_CACHE_GETS : COH_CACHE_GETX,
                                                                        clientMeta: e.meta,
                                                                        globalReadMeta: r.globalReadMeta };
         
            t_REMOTE_RESP remote_resp = RL_COH_DM_CACHE_MSHR_REMOTE_RESP { reqIdx: ?,
                                                                           val: ?,
                                                                           retry: False,
                                                                           nullResp: False };
            case (e.state)
                COH_CACHE_STATE_IM_AD:
                begin
                    new_entry.state          = (r.ownership)? COH_CACHE_STATE_IM_A : COH_CACHE_STATE_IS_A;
                    new_entry.val            = r.val; 
                    new_entry.isCacheable    = r.isCacheable;
                    new_entry.globalReadMeta = r.globalReadMeta;
                end
                COH_CACHE_STATE_IM_D:
                begin
                    mshr_release        = True;
                    local_resp.newState = (r.ownership)? COH_DM_CACHE_STATE_M : COH_DM_CACHE_STATE_S;
                    local_resp.val      = applyWriteMask(r.val, e.writeData, e.byteWriteMask);
                end
                COH_CACHE_STATE_IM_D_O, COH_CACHE_STATE_IM_D_I, COH_CACHE_STATE_IM_D_OI:
                begin
                    // delay if multiple caches (more than one cache) need to be forwarded
                    mshr_delay          = (countElem(True, e.forwardMeta) > 1);
                    mshr_release        = !mshr_delay;
                    new_val             = applyWriteMask(r.val, e.writeData, e.byteWriteMask);
                    forward_idx         = fromMaybe(?, findElem(True, e.forwardMeta));

                    // send local response to cache
                    local_resp.newState = (e.state != COH_CACHE_STATE_IM_D_O)? COH_DM_CACHE_STATE_I : 
                                          ((r.ownership)? COH_DM_CACHE_STATE_O : COH_DM_CACHE_STATE_S);
                    local_resp.val      = new_val;

                    // forward new data to a remote cache
                    // send null response (to free the table in the sourceData) if the response does not include ownership
                    send_remote_resp     = True;
                    remote_resp.reqIdx   = unpack(pack(forward_idx));
                    remote_resp.val      = new_val;
                    remote_resp.nullResp = !r.ownership;
                    
                    // update mshr entry
                    new_entry.forwardMeta[pack(forward_idx)] = False;
                    new_entry.val = new_val;
                end
            endcase

            // update mshr entry 
            if (!mshr_release)
            begin
                mshrGet.upd(r.meta, new_entry);
                mshrBusy     <= mshr_delay;
                mshrBusyIdx  <= r.meta;
                fwdNullResp  <= !r.ownership;
                debugLog.record($format("        MSHR: mshrGet entry (0x%x) update: val=0x%x, state=%d", r.meta, new_entry.val, new_entry.state));
            end
            else // release mshrGet entry
            begin
                debugLog.record($format("        MSHR: mshrGet entry (0x%x) release", r.meta));
                mshrGetValidBits.upd(r.meta, False);
                if (!mshrPutValidBits.sub(r.meta))
                begin
                    mshrReleaseW.send();
                end
            end
            
            // send response to cache
            if (mshr_release || mshr_delay)
            begin
                respLocalQ.enq(local_resp);
                debugLog.record($format("        MSHR: localResp: addr=0x%x, val=0x%x, state=%d, msgType=%s", 
                                        local_resp.addr, local_resp.val, local_resp.newState, (e.isRead)? "GETS" : "GETX"));
            end

            // forward data to a remote cache
            if (send_remote_resp)
            begin
                respToNetworkQ.enq(remote_resp);
                debugLog.record($format("        MSHR: remoteResp: reqIdx=0x%x, val=0x%x, retry=%s, nullResp=%s", 
                                        remote_resp.reqIdx, remote_resp.val, "False", (remote_resp.nullResp)? "True" : "False"));
            end
        
        end
    endrule

    (* fire_when_enabled *)
    rule mshrForward (mshrBusy);
        let e = mshrGet.sub(mshrBusyIdx);
        let new_entry  = e;
        // delay mshr entry release if multiple caches (more than one cache) need to be forwarded
        let mshr_delay = (countElem(True, e.forwardMeta) > 1);
        let forward_idx = fromMaybe(?, findElem(True, e.forwardMeta));
        
        // forward new data to a remote cache
        respToNetworkQ.enq( RL_COH_DM_CACHE_MSHR_REMOTE_RESP { reqIdx: unpack(pack(forward_idx)),
                                                               val: e.val,
                                                               retry: False,
                                                               nullResp: fwdNullResp } );
        
        debugLog.record($format("        MSHR busy: remoteResp: reqIdx=0x%x, val=0x%x, retry=%s, nullResp=%s", 
                                forward_idx, e.val, "False", fwdNullResp? "True" : "False"));
        
        // update mshr entry
        if (mshr_delay)
        begin
            new_entry.forwardMeta[pack(forward_idx)] = False;
            mshrGet.upd(mshrBusyIdx, new_entry);
        end
        else // release mshrGet entry
        begin
            mshrBusy <= False;
            mshrGetValidBits.upd(mshrBusyIdx, False);
            if (!mshrPutValidBits.sub(mshrBusyIdx))
            begin
                mshrReleaseW.send();
            end
            debugLog.record($format("        MSHR: mshrGet entry (0x%x) release", mshrBusyIdx));
        end
    endrule

    (* fire_when_enabled *)
    rule resendGetX (!activatedReqEnW && !cacheGetReqEnW && !cachePutReqEnW && !mshrGetAllocateW && !mshrBusy && retryReqQ.notFull());
        let meta = resendGetxQ.first();
        resendGetxQ.deq();
        let e = mshrGet.sub(meta);
        retryReqQ.enq(tuple2(e.addr, meta));
        resendGetxW.send();
        debugLog.record($format("        MSHR: resendGetX: resend GETX req: addr=0x%x, entry=0x%x", e.addr, meta));
    endrule

    // ====================================================================
    //
    // Methods
    //
    // ====================================================================


    // Requests that need to allocate a new MSHR entry (triggered by local requests) 
    //
    // Request for share data
    method Action getShare(t_MSHR_IDX idx,
                           t_CACHE_ADDR addr,
                           t_CACHE_CLIENT_META meta) if (!mshrBusy);

        debugLog.record($format("        MSHR: receive GETS request from cache to allocate a new entry (idx=0x%x, addr=0x%x), numPendingGetS=%x", 
                         idx, addr, numPendingGetS.value()));
        mshrGetValidBits.upd(idx, True);
        cacheGetReqEnW.send();
        numPendingGetS.up();
        getReqQ.enq( RL_COH_DM_CACHE_MSHR_GET_REQ{ idx: idx,
                                                   addr: addr,
                                                   val: ?,
                                                   writeData: ?,
                                                   byteWriteMask: unpack(pack(replicate(False))),
                                                   state: COH_CACHE_STATE_IM_AD,
                                                   meta: meta,
                                                   isGetX: False });
    endmethod
    
    // Request for data and exlusive ownership
    method Action getExclusive(t_MSHR_IDX idx,
                               t_CACHE_ADDR addr,
                               t_CACHE_WORD val,
                               t_CACHE_WORD writeData,
                               t_CACHE_MASK byteWriteMask,
                               RL_COH_DM_CACHE_COH_STATE oldState) if (!mshrBusy);

        debugLog.record($format("        MSHR: receive GETX request from cache to allocate a new entry (idx=0x%x, addr=0x%x), numPendingGetX=%x", 
                        idx, addr, numPendingGetX.value()));
        
        mshrGetValidBits.upd(idx, True);
        cacheGetReqEnW.send();
        let new_state = (oldState == COH_DM_CACHE_STATE_O)? COH_CACHE_STATE_OM_A : COH_CACHE_STATE_IM_AD;
        numPendingGetX.up();
        getReqQ.enq( RL_COH_DM_CACHE_MSHR_GET_REQ{ idx: idx,
                                                   addr: addr,
                                                   val: val,
                                                   writeData: writeData,
                                                   byteWriteMask: byteWriteMask,
                                                   state: new_state,
                                                   meta: ?,
                                                   isGetX: True });

    endmethod

    // Write back and give up ownership
    method Action putExclusive(t_MSHR_IDX idx,
                               t_CACHE_ADDR addr, 
                               t_CACHE_WORD val,
                               Bool needResp,
                               Bool isCleanWB) if (!mshrBusy);

        debugLog.record($format("        MSHR: receive PUTX request from cache to allocate a new entry (idx=0x%x, addr=0x%x)", idx, addr));
        mshrPutValidBits.upd(idx, True);
        cachePutReqEnW.send();
        putReqQ.enq( RL_COH_DM_CACHE_MSHR_PUT_REQ{ idx: idx,
                                                   addr: addr,
                                                   val: val,
                                                   needResp: needResp,
                                                   isCleanWB: isCleanWB });
    endmethod
    
    // Check if there is an available MSHR entry to handle a new miss
    method Bool entryAvailable(t_MSHR_IDX idx) if (!mshrBusy);
        return (mshrGetValidBits.sub(idx) == False) && (mshrPutValidBits.sub(idx) == False);
    endmethod

    // Return true if there is an MSHR entry released
    method Bool entryReleased() = mshrReleaseW;

    // Activated requests from the network
    method Action activatedReq(t_MSHR_IDX mshrIdx,
                               t_CACHE_ADDR addr,
                               Bool ownReq,
                               t_NW_REQ_IDX reqIdx,
                               RL_COH_CACHE_REQ_TYPE reqType) if (!mshrBusy && !getReqQ.notEmpty && !putReqQ.notEmpty && respLocalQ.notFull && respToNetworkQ.notFull);
        
        debugLog.record($format("        MSHR: %s activated request on entry=0x%x, addr=0x%x, reqType=%d", 
                                (ownReq)? "own" : "other", mshrIdx, addr, reqType));
        
        activatedReqEnW.send();
        
        let get_entry       = mshrGet.sub(mshrIdx);
        let put_entry       = mshrPut.sub(mshrIdx);
        let get_entry_valid = mshrGetValidBits.sub(mshrIdx);
        let put_entry_valid = mshrPutValidBits.sub(mshrIdx);

        curActivatedReq <= tuple4(mshrIdx, ownReq, reqIdx, reqType);
        curGetBusy      <= get_entry_valid; 
        curPutBusy      <= put_entry_valid; 

        if (get_entry_valid && pack(get_entry.addr) == pack(addr))
        begin
            curGetEntry.wset(get_entry);
        end
        else if (put_entry_valid &&& pack(put_entry.addr) == pack(addr))
        begin
            curPutEntry.wset(put_entry);
        end
    endmethod

    // Responses received from the network
    method Action recvResp(t_CACHE_FILL_RESP resp);
        respFromNetworkQ.enq(resp); 
        numBufferedResps.up();
    endmethod
    
    // Return true if respFromNetworkQ is almost full
    method Bool dataRespQAlmostFull() = respAlmostFull;

    // Local responses to cache 
    method ActionValue#(RL_COH_DM_CACHE_MSHR_LOCAL_RESP#(t_CACHE_ADDR, 
                                                         t_CACHE_WORD,
                                                         t_CACHE_CLIENT_META)) localResp();
        let r = respLocalQ.first();
        respLocalQ.deq();
        return r;
    endmethod

    // Remote responses to network
    method ActionValue#(RL_COH_DM_CACHE_MSHR_REMOTE_RESP#(t_NW_REQ_IDX,
                                                          t_CACHE_WORD)) remoteResp();
        let r = respToNetworkQ.first();
        respToNetworkQ.deq();
        return r;
    endmethod                                                      

    // Retry request to network
    method ActionValue#(Tuple2#(t_CACHE_ADDR, t_MSHR_IDX)) retryReq();
        let r = retryReqQ.first();
        retryReqQ.deq();
        return r;
    endmethod
    
    // Return true if a read request has been processed (received activated GETS req)
    method Bool getShareProcessed() = getsProcessedW;
    // Return true if a write request has been processed (received response for GETX)
    method Bool getExclusiveProcessed() = getxProcessedW;
    // Return true if there is at least one pending read request
    method Bool getSharePending() = (numPendingGetS.value() != 0);
    // Return true if there is at least one pending write request
    method Bool getExclusivePending() = (numPendingGetX.value() != 0);

endmodule

