//
// Copyright (c) 2014, Intel Corporation
// All rights reserved.
//
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are met:
//
// Redistributions of source code must retain the above copyright notice, this
// list of conditions and the following disclaimer.
//
// Redistributions in binary form must reproduce the above copyright notice,
// this list of conditions and the following disclaimer in the documentation
// and/or other materials provided with the distribution.
//
// Neither the name of the Intel Corporation nor the names of its contributors
// may be used to endorse or promote products derived from this software
// without specific prior written permission.
//
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
// AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
// IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
// ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE
// LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
// CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
// SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
// INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
// CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
// ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
// POSSIBILITY OF SUCH DAMAGE.
//

//
// A generic cache class (n-way set associative) for caching data in BRAM.
// Classes building a cache must provide an interface class to the source
// data of type RL_SA_CACHE_SOURCE_DATA (defined below).  The cache
// takes a number of parameters: the address and data types, the number of
// sets and the number of ways within each set.
//
// The cache may either be write-back (the default) or write-through.  For
// write through caches it is the callers responsibility to do the write
// to backing storage.  This cache class merely skips setting of the dirty
// bit on writes in write-through mode.
//

// Library imports.

import FIFO::*;
import FIFOF::*;
import Vector::*;
import SpecialFIFOs::*;
import List::*;
import DefaultValue::*;
import ConfigReg::*;

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
// Set associative cache interface.  nTagExtraLowBits is used just for
// debugging.  This specified number of low bits are prepanded to cache
// tags so addresses match those seen in other modules.
//
// t_CACHE_READ_META is metadata associated with a reference.  Metadata is
// passed to the backing store for fills.  The metadata is not stored in
// the cache.
//
interface RL_SA_BRAM_CACHE#(type t_CACHE_ADDR,
                            type t_CACHE_WORD,
                            numeric type nWordsPerLine,
                            type t_CACHE_READ_META);

    // Read up to a full line.  Read from backing store if not already cached.
    // The read response is guaranteed to return at least the requested
    // word in the line.  If more of the line is already available it will
    // be returned as well.
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

    method ActionValue#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META)) readResp();

    // Some clients need the address to route responses.  Having a peek method
    // for response addresses avoids extra buffering in these clients.
    method t_CACHE_ADDR peekRespAddr();

    // Predicate to test whether a read response is ready this cycle.
    method Bool readRespReady();
    

    // Write a word to a cache line.  Word index 0 corresponds to the
    // low bits of a cache line.
    method Action write(t_CACHE_ADDR addr,
                        t_CACHE_WORD val,
                        Bit#(TLog#(nWordsPerLine)) wordIdx);
    
    // Invalidate & flush requests.  Both write dirty lines back.  Invalidate drops
    // the line from the cache.  Flush keeps the line in the cache.  A response
    // is returned for invalOrFlushWait iff sendAck is true.
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action invalOrFlushWait();
    
    //
    // Set cache mode.  Mostly useful for debugging.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
    method Action setRecentLineCacheMode(Bool enabled);

    //
    // Debug scan state.  The cache can't instantiate a debug scan node because
    // the debug scan code depends on libRL.  Instantiating a node here would
    // create a source dependence loop.  Instead, a list of name/value pairs
    // is available for use by a client.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
    
    interface RL_CACHE_STATS#(t_CACHE_READ_META) stats;

endinterface: RL_SA_BRAM_CACHE

//
// Source data fill response
//
typedef struct
{
    t_CACHE_LINE val;
    t_CACHE_ADDR addr;
    Bool isCacheable;
    t_CACHE_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_SA_BRAM_CACHE_FILL_RESP#(type t_CACHE_LINE,
                            type t_CACHE_ADDR,
                            type t_CACHE_META)
    deriving (Eq, Bits);


//
// The caller must provide an instance of the RL_SA_BRAM_CACHE_SOURCE_DATA interface
// so the cache can read and write data from the next level in the hierarchy.
//
interface RL_SA_BRAM_CACHE_SOURCE_DATA#(type t_CACHE_ADDR,
                                        type t_CACHE_LINE,
                                        numeric type nWordsPerLine,
                                        type t_CACHE_META);

    // Read request and response with data
    method Action readReq(t_CACHE_ADDR addr,
                          t_CACHE_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);
    
    method ActionValue#(RL_SA_BRAM_CACHE_FILL_RESP#(t_CACHE_LINE,
                                                    t_CACHE_ADDR, 
                                                    t_CACHE_META)) readResp();
    // Asynchronous write (no response)
    method Action write(t_CACHE_ADDR addr, 
                        Vector#(nWordsPerLine, Bool) wordValidMask, 
                        t_CACHE_LINE val);
    
    // Pass invalidate and flush requests down the hierarchy.  If sendAck is
    // true then invalOrFlushWait must block until the operation is complete.
    // If sendAck is false invalOrflushWait will not be called.
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
    method Action invalOrFlushWait();

endinterface: RL_SA_BRAM_CACHE_SOURCE_DATA

typedef 256 RL_SA_BRAM_CACHE_MAF_ENTRIES;

typedef enum
{
    RL_SA_CACHE_READ,
    RL_SA_CACHE_WRITE,
    RL_SA_CACHE_FLUSH,
    RL_SA_CACHE_INVAL
}
RL_SA_BRAM_CACHE_ACTION
    deriving (Eq, Bits);


typedef struct
{
    Bit#(TLog#(nWordsPerLine)) wordIdx;
    // Meta-data associated with the reference.  Meta-data has meaning only to the
    // caller.
    t_CACHE_READ_META readMeta;
    RL_CACHE_GLOBAL_READ_META globalReadMeta;
}
RL_SA_BRAM_CACHE_READ_REQ#(numeric type nWordsPerLine, 
                           type t_CACHE_READ_META)
    deriving (Eq, Bits);

//
// Meta-data associated with a write request.
//
typedef struct
{
    Bit#(WRITE_DATA_HEAP_IDX_SZ) dataIdx;
    Bit#(TLog#(nWordsPerLine)) wordIdx;
}
RL_SA_BRAM_CACHE_WRITE_REQ#(numeric type nWordsPerLine)
    deriving (Eq, Bits);

typedef union tagged
{
    RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META) HCOP_READ;
    RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine) HCOP_WRITE;
    Bool HCOP_INVAL;
    Bool HCOP_FLUSH_DIRTY;
}
RL_SA_BRAM_CACHE_REQ#(numeric type nWordsPerLine, 
                      type t_CACHE_READ_META)
    deriving(Bits, Eq);



// ========================================================================
//
// mkCacheSetAssocWithBRAM --
//    A wrapper of a set associative cache implemented with BRAM.
//
//    NOTE: mkCacheSetAssocWithBRAM may return read responses out of order 
//          relative to the request order!  For in-order responses the 
//          caller must add a tag to the t_CACHE_READ_META type and use the
//          tag to sort the responses.  A SCOREBOARD_FIFO would do the job.
//
// ========================================================================

module mkCacheSetAssocWithBRAM#(RL_SA_BRAM_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_MAF_IDX) sourceData,
                                NumTypeParam#(nSets) param0,
                                NumTypeParam#(nWays) param1,
                                NumTypeParam#(nTagExtraLowBits) param2,
                                DEBUG_FILE debugLog)
    // interface:
        (RL_SA_BRAM_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),

              // Write word size must tile into cache line
              Bits#(Vector#(nWordsPerLine, t_CACHE_WORD), t_CACHE_LINE_SZ),

              // Cache address size must be no larger than 128 bits because
              // of the hash function.
              Add#(t_CACHE_ADDR_SZ, a__, 128),

              // Set index and tag.  Set index size + tag size == address size.
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Bits#(t_CACHE_SET_IDX, t_CACHE_SET_IDX_SZ),
              Alias#(RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets), t_CACHE_TAG),

              // Set size must be no longer than 32 bits (for set filter)
              Add#(t_CACHE_SET_IDX_SZ, b__, 32),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WORD_IDX),
              Alias#(Bit#(TLog#(RL_SA_BRAM_CACHE_MAF_ENTRIES)), t_MAF_IDX),

              // Unbelievably ugly tautologies required by the compiler:
              Add#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets)), TLog#(nSets), t_CACHE_ADDR_SZ),
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),
              Log#(nWays, TLog#(nWays)),
              Add#(TLog#(TExp#(TLog#(nSets))), 0, TLog#(nSets)),
              Add#(TLog#(TDiv#(TExp#(TLog#(nSets)), 2)), x__, TLog#(nSets)));

    RL_SA_BRAM_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META) cache = ?;

    // Special case: multi-word directed mapped cache
    if (valueOf(nWays) == 1)
    begin
        cache <- mkCacheMultiWordDirectMapped(sourceData, param0, param2, debugLog);
    end
    else
    begin
        cache <- mkCacheSetAssocWithBRAMImpl(sourceData, param0, param1, param2, debugLog);
    end

    return cache;

endmodule


// ===================================================================
//
// Special case: Multi-word direct mapped cache implementation
//
// ===================================================================

typedef struct
{
    RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets) tag;
    Bool dirty;
    Vector#(nWordsPerLine, Bool) wordValid;
}
RL_MW_DM_CACHE_METADATA#(numeric type t_CACHE_ADDR_SZ, numeric type nWordsPerLine, numeric type nSets)
    deriving(Bits, Eq);

instance DefaultValue#(RL_MW_DM_CACHE_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets));
    defaultValue = RL_MW_DM_CACHE_METADATA { tag: ?,
                                             dirty: False,
                                             wordValid: replicate(False) }; 
endinstance

typedef struct
{
    t_CACHE_TAG     tag;
    t_CACHE_SET_IDX set;
}
RL_MW_DM_CACHE_REQ_BASE#(type t_CACHE_TAG,
                         type t_CACHE_SET_IDX)
    deriving(Bits, Eq);


module mkCacheMultiWordDirectMapped#(RL_SA_BRAM_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_MAF_IDX) sourceData,
                                     NumTypeParam#(nSets) param0,
                                     NumTypeParam#(nTagExtraLowBits) param1,
                                     DEBUG_FILE debugLog)
    // interface:
        (RL_SA_BRAM_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),

              // Write word size must tile into cache line
              Bits#(Vector#(nWordsPerLine, t_CACHE_WORD), t_CACHE_LINE_SZ),

              // Cache address size must be no larger than 128 bits because
              // of the hash function.
              Add#(t_CACHE_ADDR_SZ, a__, 128),

              // Set index and tag.  Set index size + tag size == address size.
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Bits#(t_CACHE_SET_IDX, t_CACHE_SET_IDX_SZ),
              Alias#(RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets), t_CACHE_TAG),

              // Set size must be no longer than 32 bits (for set filter)
              Add#(t_CACHE_SET_IDX_SZ, b__, 32),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              Alias#(RL_MW_DM_CACHE_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets), t_METADATA),
              Alias#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META), t_CACHE_LOAD_RESP),
              Alias#(RL_MW_DM_CACHE_REQ_BASE#(t_CACHE_TAG, t_CACHE_SET_IDX), t_CACHE_REQ_BASE),
              Alias#(RL_SA_BRAM_CACHE_REQ#(nWordsPerLine, t_CACHE_READ_META), t_CACHE_REQ),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WORD_IDX),
              Alias#(RL_SA_CACHE_WRITE_INFO#(t_CACHE_WORD, t_CACHE_WORD_IDX), t_CACHE_WRITE_INFO),
              Alias#(Vector#(nWordsPerLine, Bool), t_CACHE_WORD_VALID_MASK),
       
              Bits#(t_CACHE_REQ, t_CACHE_REQ_SZ),

              Alias#(Bit#(TLog#(RL_SA_BRAM_CACHE_MAF_ENTRIES)), t_MAF_IDX),

              // Unbelievably ugly tautologies required by the compiler:
              Add#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets)), TLog#(nSets), t_CACHE_ADDR_SZ),
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),
              Add#(TLog#(TExp#(TLog#(nSets))), 0, TLog#(nSets)),
              Add#(TLog#(TDiv#(TExp#(TLog#(nSets)), 2)), x__, TLog#(nSets)));

    // ***** Elaboration time checks of types
    // The interface allows for a number of sets that isn't a
    // power of 2, but the implementation currently does not.
    if(valueof(nSets) != valueof(TExp#(TLog#(nSets))))
    begin
        error("nSets must be a power of 2");
    end
    
    // Cache Storage
    
    // Metadata
    BRAM#(t_CACHE_SET_IDX, t_METADATA) metaStore = ?; 
    
    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        metaStore <- mkBRAMInitialized(defaultValue);
    end
    else if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 1)
    begin
        // Cache implemented as 4 BRAM banks with I/O buffering to allow
        // more time to reach memory.
        NumTypeParam#(4) p_banks = ?;
        metaStore <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                     mkBRAMInitializedBuffered(defaultValue));
    end
    else
    begin
        // Cache implemented as 4 half-speed BRAM banks.
        NumTypeParam#(4) p_banks = ?;

        // Add buffering.  This accomplishes two things:
        //   1. It adds a fully scheduled stage (without conservative conditions)
        //      that allows requests to go to banks that aren't busy.
        //   2. Buffering supports long wires.
        let meta_slow = mkSlowMemoryM(mkBRAMInitializedClockDivider(defaultValue), True);
        metaStore <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW, meta_slow);
    end

    // Values
    Vector#(nWordsPerLine, BRAM#(t_CACHE_SET_IDX, t_CACHE_WORD)) dataStore = ?;

    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        dataStore <- replicateM(mkBRAMSized(valueof(nSets)));
    end
    else if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 1)
    begin
        NumTypeParam#(4) p_banks = ?;
        dataStore <- replicateM(mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                                mkBRAMSizedBuffered(valueof(nSets)/4)));
    end
    else
    begin
        NumTypeParam#(4) p_banks = ?;
        let data_slow = mkSlowMemoryM(mkBRAMSizedClockDivider(valueof(nSets)/4), True);
        dataStore <- replicateM(mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW, data_slow));
    end

    // ***** Internal state *****

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(Bit#(WRITE_DATA_HEAP_IDX_SZ), t_CACHE_WORD) reqInfo_writeData <- mkMemoryHeapLUTRAM();
    MEMORY_HEAP#(t_MAF_IDX,Tuple4#(t_CACHE_READ_META, t_CACHE_WORD_IDX, t_CACHE_WORD_VALID_MASK, Bool)) mafTable <- mkMemoryHeapUnionBRAM();

    // Is the cache write back?  If not, never set a dirty bit.  It is then the
    // responsibility of the caller to write values to backing storage.
    Reg#(RL_SA_CACHE_MODE) cacheMode <- mkReg(RL_SA_MODE_WRITE_BACK);
    function Bool writeBackCache() = (cacheMode == RL_SA_MODE_WRITE_BACK);
    function Bool cacheEnabled() = (pack(cacheMode)[1] == 0);

    // Filter for allowing one live operation per cache set.
    COUNTING_FILTER#(t_CACHE_SET_IDX, 1) setFilter <- mkCountingFilter(debugLog);

    // ***** Queues between internal pipeline stages *****

    // Incoming requests
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) newReqQ <- mkFIFOF();
    // Cache lookup queue
    FIFOF#(Maybe#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ))) cacheLookupQ = ?;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_METADATA, Bool)) dataLookupQ = ?;
`endif

    // Fill for read path
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, t_MAF_IDX, RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META), Maybe#(t_CACHE_WORD_VALID_MASK), Bool)) fillReqQ <- mkFIFOF();
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, t_CACHE_LINE, RL_CACHE_GLOBAL_READ_META, t_MAF_IDX, Bool)) mafLookupQ <- mkFIFOF();

    // Inval or flush path
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, Bool)) invalOrFlushQ <- mkFIFOF();

    // Exit from all paths
    FIFOF#(t_CACHE_SET_IDX) doneQ <- mkFIFOF();

    // Read responses may be returned out of order relative to request order!
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META), t_CACHE_LINE, t_CACHE_WORD_VALID_MASK, Bool)) readRespToClientQ_OOO <- mkFIFOF();

    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        cacheLookupQ <- mkFIFOF();
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        dataLookupQ <- mkFIFOF();
`endif
    end
    else
    begin
        cacheLookupQ <- mkSizedFIFOF(4);
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        dataLookupQ <- mkSizedFIFOF(4);
`endif
    end

    RWire#(t_CACHE_READ_META) readMissW          <- mkRWire();
    RWire#(t_CACHE_READ_META) writeMissW         <- mkRWire();
    RWire#(t_CACHE_READ_META) readHitW           <- mkRWire();
    RWire#(t_CACHE_READ_META) writeHitW          <- mkRWire();
    PulseWire invalEntryW        <- mkPulseWire();
    PulseWire forceInvalLineW    <- mkPulseWire();
    PulseWire dirtyEntryFlushW   <- mkPulseWire();

    // ***** Indexing functions *****
    //
    // Functions for converting from address to tag and set or vice versa.
    //
    function Tuple2#(t_CACHE_TAG, t_CACHE_SET_IDX) cacheTagAndSet(t_CACHE_ADDR addr);
        return unpack(hashBits(addr));
    endfunction

    function t_CACHE_ADDR cacheAddr(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        t_CACHE_ADDR hashed_addr = { tag, pack(set) };
        return hashBits_inv(hashed_addr);
    endfunction

    //
    // debugAddr --
    //     Pretty printer for converting cache addresses to system addresses.
    //     Adds trailing 0's that were dropped from cache addresses because they
    //     are inside a cache line.
    //
    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddr(t_CACHE_ADDR addr);
        Bit#(nTagExtraLowBits) zero = 0;
        return { addr, zero };
    endfunction

    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddrFromTag(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        Bit#(nTagExtraLowBits) zero = 0;
        return { cacheAddr(tag, set), zero };
    endfunction
    
    //
    // cache access functions
    //
    function Action cacheLineDataReadReq(t_CACHE_SET_IDX set);
        action
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                dataStore[b].readReq(set);
            end
        endaction
    endfunction
    
    function Action cacheLineDataWrite(t_CACHE_SET_IDX set, t_CACHE_WORD_VALID_MASK mask, t_CACHE_LINE val);
        action
            Vector#(nWordsPerLine, t_CACHE_WORD) words = unpack(pack(val));
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                if (mask[b])
                begin
                    dataStore[b].write(set, words[b]);
                end
            end
        endaction
    endfunction

    function ActionValue#(t_CACHE_LINE) getCacheLineDataResp();
        actionvalue
            Vector#(nWordsPerLine, t_CACHE_WORD) v = newVector();
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                let d <- dataStore[b].readRsp();
                v[b] = d;
            end
            t_CACHE_LINE line_data = unpack(pack(v));
            return line_data;
        endactionvalue
    endfunction

    // ***** Rules ***** //

    // ====================================================================
    //
    // All incoming requests start here with handleIncomingReq
    //
    // ====================================================================

    //
    // Maintain a side buffer of requests to cache sets that already have
    // in-flight conflicting requests.  This allows non-conflicting requests
    // to proceed.
    //
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) sideReqQ <-
        mkSizedFIFOF(valueOf(RL_SA_CONFLICTQ_ENTRIES));

    // A very simple filter to detect lines with requests already in the side
    // cache.
    LUTRAM#(Bit#(6), Bit#(3)) sideReqFilter <- mkLUTRAM(0);
    Reg#(Bit#(1)) newReqArb <- mkReg(0);
    Wire#(Tuple3#(Bool,
                  Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ),
                  Maybe#(CF_OPAQUE#(t_CACHE_SET_IDX, 1)))) curReq <- mkWire();
    
    // Track whether the heads of newReqQ and sideReqQ are blocked.  
    // Once blocked, a queue stays blocked until either the head is removed or 
    // a cache index is unlocked when an in-flight request is completed.
    Reg#(Bool) newReqNotBlocked      <- mkConfigReg(True);
    Reg#(Bool) retryReqNotBlocked    <- mkConfigReg(True);
    PulseWire  startSideReqW         <- mkPulseWire();
    PulseWire  setFilterRemoveW      <- mkPulseWire();

    // Wires for managing cacheLookupQ
    RWire#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) newCacheLookupReqW <- mkRWire();
    PulseWire newCacheLookupValidW <- mkPulseWire();
    
    //
    // pickReqQ --
    //     Decide whether to consider the new request or side request queue
    //     this cycle.  Filtering both is too expensive.
    //
    rule pickReqQueue (cacheLookupQ.notFull());
        //
        // New requests win over side requests if there is a new request
        // and the arbiter is non-zero.  If the arbitration counter newReqArb
        // is larger than 1 bit this favors new requests over side-buffer
        // requests in an effort to have as many requests in flight as possible.
        //
        Bool new_req_avail = newReqQ.notEmpty && newReqNotBlocked;
        Bool side_req_avail = sideReqQ.notEmpty && retryReqNotBlocked;
        Bool pick_new_req = new_req_avail && ((newReqArb != 0) || ! side_req_avail);
    
        let r = pick_new_req ? newReqQ.first() : sideReqQ.first();

        match {.req_base, .req} = r;
        let tag = req_base.tag;
        let set = req_base.set;
        
        // speculatively read meta and data stores
        newCacheLookupReqW.wset(r);
`ifdef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        cacheLineDataReadReq(set);
`endif
        metaStore.readReq(set);
        
        // Update arbiter now that a request has been posted.  Arbiter update
        // is tied to cache requests in order to support storage that
        // doesn't accept a request every cycle, such as BRAM running
        // with a divided block.  Updating the arbiter without this connection
        // can trigger harmonics that result in live locks.
        newReqArb <= newReqArb + 1;

        // In order to preserve read/write and write/write order, the
        // request must either come from the side buffer or be a new request
        // referencing a line not already in the side buffer.
        //
        // The array sideReqFilter tracks lines active in the side request
        // queue.
        if (! pick_new_req || sideReqFilter.sub(resize(set)) == 0)
        begin
            curReq <= tuple3(pick_new_req, r, setFilter.test(set));
        end
        else
        begin
            curReq <= tuple3(pick_new_req, r, tagged Invalid);
        end
    endrule

    //
    // startReq --
    //     Start the current request if the line is not busy.
    //
    (* fire_when_enabled *)
    rule startReq (tpl_3(curReq) matches tagged Valid .filter_state);
        match {.pick_new_req, .r, .cf_opaque} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        setFilter.set(filter_state);
        newCacheLookupValidW.send();
        debugLog.record($format("  FWD %s to ReqQ: addr=0x%x, set=0x%x",
                                pick_new_req ? "new" : "side",
                                debugAddrFromTag(tag, set), set));
        if (pick_new_req)
        begin
            newReqQ.deq();
        end
        else
        begin
            sideReqQ.deq();
            startSideReqW.send();
            sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) - 1);
        end
    endrule

    //
    // shuntNewReq --
    //     If the current request is new (not a shunted request) and the
    //     line is busy, shunt the new request to a side queue in order to
    //     attempt to process a later request that may be ready to go.
    //
    //     This rule will not fire if startReq fires.
    //
    match {.curReq_req_base, .curReq_req} = tpl_2(curReq);
    
    function Bool isOrderedReq(t_CACHE_REQ req);
        if (req matches tagged HCOP_READ .rReq &&& rReq.globalReadMeta.orderedSourceDataReqs == True)
            return True;
        else
            return False;
    endfunction

    (* fire_when_enabled *)
    rule shuntNewReq (tpl_1(curReq) &&
                      ! isOrderedReq(curReq_req) &&
                      (sideReqFilter.sub(resize(curReq_req_base.set)) != maxBound) &&
                      ! isValid(tpl_3(curReq)));
        
        match {.pick_new_req, .r, .cf_opaque} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        debugLog.record($format("  SIDE shunt req: addr=0x%x, set=0x%x",
                                debugAddrFromTag(tag, set), set));

        sideReqQ.enq(r);
        newReqQ.deq();

        // Note line present in sideReqQ
        sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) + 1);
    endrule
    
    //
    // blockNewReq --
    //     Check if the head of newReqQ is blocked by busy cache lines and 
    // cannot be shunt to retry queue. 
    //
    (* fire_when_enabled *)
    rule blockNewReq (tpl_1(curReq) && ( isOrderedReq(curReq_req) || 
                      (sideReqFilter.sub(resize(curReq_req_base.set)) == maxBound) ) &&
                      ! isValid(tpl_3(curReq)));
        newReqNotBlocked <= False;
        debugLog.record($format("  New req blocked by busy: addr=0x%x", 
                        debugAddrFromTag(curReq_req_base.tag, curReq_req_base.set)));
    endrule
    
    //
    // unblockLocalReq --
    //     Unblock newReqQ when a sideReq is processed or an inflight request is complete. 
    //
    (* fire_when_enabled *)
    rule unblockNewReq (startSideReqW || setFilterRemoveW);
        newReqNotBlocked <= True;
        debugLog.record($format("  Unblock newReqQ"));
    endrule
    
    //
    // blockSideReq --
    //     Check if the head of the sideReqQ is blocked by busy cache lines.
    //
    (* fire_when_enabled *)
    rule blockSideReq (!tpl_1(curReq) && ! isValid(tpl_3(curReq)));
        retryReqNotBlocked <= False;
        debugLog.record($format("  Side req blocked by busy: addr=0x%x",
                        debugAddrFromTag(curReq_req_base.tag, curReq_req_base.set)));
    endrule
    
    //
    // unblockSideReq --
    //     Unblock the sideReqQ when an inflight request is complete. 
    //
    (* fire_when_enabled *)
    rule unblockLocalRetryReq (setFilterRemoveW);
        retryReqNotBlocked <= True;
        debugLog.record($format("  Unblock sideReqQ"));
    endrule
    
    //
    // Write cacheLookupQ to indicate whether a new request was started
    // this cycle.
    //
    (* fire_when_enabled *)
    rule didLookup (newCacheLookupReqW.wget() matches tagged Valid .r);
        // Was a valid new request started?
        if (newCacheLookupValidW)
        begin
            match {.req_base, .req} = r;
            cacheLookupQ.enq(tagged Valid r);
            debugLog.record($format("    Lookup valid, set=0x%x", req_base.set));
        end
        else
        begin
            cacheLookupQ.enq(tagged Invalid);
            debugLog.record($format("    Speculative lookup dropped"));
        end
    endrule
    
    // ====================================================================
    //
    // Drain (failed speculative read)
    //
    // ====================================================================

    rule drainRead (! isValid(cacheLookupQ.first));
        cacheLookupQ.deq();
        let meta <- metaStore.readRsp();
`ifdef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
        let data <- getCacheLineDataResp();
`endif        
    endrule
    
    // ======================================================================
    //
    // Pipelined cache lookup if RL_SA_BRAM_CACHE_PIPELINE_EN is enabled.
    // Determine whether there is a tag match and prefetch data in the first 
    // stage.   
    //
    // ======================================================================

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule cacheTagCheck (cacheLookupQ.first() matches tagged Valid .r);
        match {.req_base, .req} = r;
        cacheLookupQ.deq();
        let meta <- metaStore.readRsp();
        let tag = req_base.tag;
        let set = req_base.set;
        cacheLineDataReadReq(set);
        if (meta.tag == tag)
        begin
            dataLookupQ.enq(tuple4(req_base, req, meta, True));
            debugLog.record($format("  cacheTagCheck: tag matched, set=0x%x", set));
        end
        else
        begin
            dataLookupQ.enq(tuple4(req_base, req, meta, False));
        end
    endrule
`endif
    
    // ====================================================================
    //
    // Inval / flush path
    //
    // Two stage path for invalidate or flush requests.  First stage
    // looks up the address in the cache.  If the line is present and dirty,
    // the second stage flushes it to the backing storage.  The third
    // stage responds with an ACK that storage is consistent, if requested.
    //
    // ====================================================================

    function Bool reqIsInvalOrFlush(t_CACHE_REQ req);
        if (req matches tagged HCOP_INVAL .needAck)
            return True;
        else if (req matches tagged HCOP_FLUSH_DIRTY .needAck)
            return True;
        else
            return False;
    endfunction

    //
    // handleInvalOrFlush --
    //     Invalidate and flush requests have similar handling.  Both write
    //     back a dirty matching line.  Flush preserves the now clean line
    //     in the cache.
    //
    (* conservative_implicit_conditions *)
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule handleInvalOrFlush (reqIsInvalOrFlush(tpl_2(dataLookupQ.first())));
        match {.req_base, .req, .meta, .tag_matched} = dataLookupQ.first();
        dataLookupQ.deq();
`else
    rule handleInvalOrFlush (cacheLookupQ.first() matches tagged Valid .r &&& reqIsInvalOrFlush(tpl_2(r)));
        match {.req_base, .req} = r;
        cacheLookupQ.deq();
        let meta <- metaStore.readRsp();
`endif
        let line <- getCacheLineDataResp();

        let tag = req_base.tag;
        let set = req_base.set;

        Bool need_ack = ?;
        Bool is_inval = ?;

        case (req) matches
        tagged HCOP_INVAL .needACK:
        begin
            need_ack = needACK;
            is_inval = True;
            debugLog.record($format("  Process request: INVAL addr=0x%x, set=0x%x, needAck=%s", 
                            debugAddrFromTag(tag, set), set, needACK? "True" : "False"));
        end
        tagged HCOP_FLUSH_DIRTY .needACK:
        begin
            need_ack = needACK;
            is_inval = False;
            debugLog.record($format("  Process request: FLUSH addr=0x%x, set=0x%x, needAck=%s", 
                            debugAddrFromTag(tag, set), set, needACK? "True" : "False"));
        end
        endcase

        Bool found_dirty_line = False;
        let new_meta = meta;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        if (tag_matched)
`else            
        if (meta.tag == tag)
`endif
        begin
            if (meta.dirty && !is_inval)
            begin
                // Found dirty line.  Prepare for write back.
                // FLUSH:  Line no longer dirty.  Update meta data.
                new_meta.dirty = False;
                found_dirty_line = True;
                dirtyEntryFlushW.send();
                debugLog.record($format("  FLUSH: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                                debugAddrFromTag(tag, set), set, meta.wordValid, line));
                sourceData.write(cacheAddr(tag, set), meta.wordValid, line);
            end
            if (is_inval)
            begin
                // Invalidate line
                forceInvalLineW.send();
                new_meta.wordValid = replicate(False);
                new_meta.dirty = False;
                debugLog.record($format("  INVAL: addr=0x%x, set=0x%x, mask=0x%x", 
                                debugAddrFromTag(tag, set), set, meta.wordValid));
            end
            metaStore.write(set, new_meta);
            debugLog.record($format("  FLUSH/INVAL HIT %s: addr=0x%x, set=0x%x", 
                            (found_dirty_line ? "dirty" : "clean"), debugAddrFromTag(tag, set), set));
        end
        
        if (need_ack)
        begin
            invalOrFlushQ.enq(tuple2(req_base, is_inval)); 
        end
        else
        begin
            doneQ.enq(set);
        end
    endrule

    //
    //  fwdInvalOrFlush --
    //    Forward invalidate or flush requests down to next level memory
    //
    rule fwdInvalOrFlush (True);
        match {.req_base, .is_inval} = invalOrFlushQ.first();
        invalOrFlushQ.deq();
        let set = req_base.set;
        let tag = req_base.tag;
        if (is_inval)
        begin
            sourceData.invalReq(cacheAddr(tag, set), True);
        end
        else
        begin
            sourceData.flushReq(cacheAddr(tag, set), True);
        end
        doneQ.enq(set);
    endrule

    // ====================================================================
    //
    // Read and Write data path.
    //
    // ====================================================================

    //
    // handleRead --
    //     Cache read path.
    //
    (* conservative_implicit_conditions *)
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule handleRead (tpl_2(dataLookupQ.first()) matches tagged HCOP_READ .rReq);
        match {.req_base, .req, .meta, .tag_matched} = dataLookupQ.first();
        dataLookupQ.deq();
`else
    rule handleRead (cacheLookupQ.first() matches tagged Valid .r &&& tpl_2(r) matches tagged HCOP_READ .rReq);
        match {.req_base, .req} = r;
        cacheLookupQ.deq();
        let meta <- metaStore.readRsp();
`endif
        let line <- getCacheLineDataResp();
        
        let tag = req_base.tag;
        let set = req_base.set;
        
        debugLog.record($format("  Process request: READ addr=0x%x, set=0x%x", 
                        debugAddrFromTag(tag, set), set));
        
        Bool needFill = True;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        if (tag_matched)
`else            
        if (meta.tag == tag)
`endif
        begin
            //
            // Line hit!
            //
            if (meta.wordValid[rReq.wordIdx])
            begin
                // Word hit!
                readHitW.wset(rReq.readMeta);
                readRespToClientQ_OOO.enq(tuple5(req_base, rReq, line, meta.wordValid, True));
                // Done with this read request
                doneQ.enq(set);
                debugLog.record($format("  Read HIT: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                                debugAddrFromTag(tag, set), set, meta.wordValid, line));
            end
            else
            begin
                // Line valid but word in line is not.  Fill.
                let maf_idx <- mafTable.malloc();
                fillReqQ.enq(tuple5(req_base, maf_idx, rReq, tagged Valid meta.wordValid, meta.dirty));
                // Mark all words valid in the line.  They will be after
                // the fill completes.
                let new_meta = meta;
                new_meta.wordValid = replicate(True);
                metaStore.write(set, new_meta);
                debugLog.record($format("  Read WORD MISS: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                                debugAddrFromTag(tag, set), set, meta.wordValid, line));
            end
        end
        else 
        begin
            // Line Miss.  
            let maf_idx <- mafTable.malloc();
            fillReqQ.enq(tuple5(req_base, maf_idx, rReq, tagged Invalid, False));
            debugLog.record($format("  Read LINE MISS: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                            debugAddrFromTag(tag, set), set, meta.wordValid, line));
            invalEntryW.send();
            // Need to flush old data?
            if (meta.dirty)
            begin
                dirtyEntryFlushW.send();
                sourceData.write(cacheAddr(meta.tag, set), meta.wordValid, line);
                debugLog.record($format("  FLUSH: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                                debugAddrFromTag(meta.tag, set), set, meta.wordValid, line));
            end
            // Mark all words valid in the line.  They will be after the fill completes
            metaStore.write(set, RL_MW_DM_CACHE_METADATA{ tag: tag, dirty: False, wordValid: replicate(True)});
        end
    endrule

    //
    // handleWrite --
    //     Cache write path.
    //
    (* conservative_implicit_conditions *)
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule handleWrite (tpl_2(dataLookupQ.first()) matches tagged HCOP_WRITE .wReq);
        match {.req_base, .req, .meta, .tag_matched} = dataLookupQ.first();
        dataLookupQ.deq();
`else
    rule handleWrite (cacheLookupQ.first() matches tagged Valid .r &&& tpl_2(r) matches tagged HCOP_WRITE .wReq);
        match {.req_base, .req} = r;
        cacheLookupQ.deq();
        let meta <- metaStore.readRsp();
`endif
        let line <- getCacheLineDataResp();
        
        let tag = req_base.tag;
        let set = req_base.set;
        let w_data = reqInfo_writeData.sub(wReq.dataIdx);
        reqInfo_writeData.free(wReq.dataIdx);
        let new_meta = meta;

        debugLog.record($format("  Process request: WRITE addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        if (tag_matched)
`else            
        if (meta.tag == tag)
`endif
        begin
            //
            // Line hit!
            //
            writeHitW.wset(?);
            debugLog.record($format("  Write HIT: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                           debugAddrFromTag(tag, set), set, meta.wordValid, line));
            if (! writeBackCache())
            begin
                // Send all writes to backing storage if in write-through mode.
                Vector#(nWordsPerLine, Bool) mask = replicate(False);
                mask[wReq.wordIdx] = True;
                Vector#(nWordsPerLine, t_CACHE_WORD) val = replicate(w_data);
                sourceData.write(cacheAddr(tag, set), mask, unpack(pack(val)));
                debugLog.record($format("  WRITE Through Word: addr=0x%x, wordIdx=%0d, data=0x%x", 
                                debugAddrFromTag(tag, set), wReq.wordIdx, w_data));
            end
        end
        else
        begin
            // Line Miss.  
            // Need to flush old data?
            new_meta = RL_MW_DM_CACHE_METADATA{tag: tag, dirty: False, wordValid: replicate(False)};
            debugLog.record($format("  WRITE LINE MISS: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                            debugAddrFromTag(tag, set), set, meta.wordValid, line));
            writeMissW.wset(?);
            invalEntryW.send();
            if (meta.dirty)
            begin
                dirtyEntryFlushW.send();
                sourceData.write(cacheAddr(meta.tag, set), meta.wordValid, line);
                debugLog.record($format("  FLUSH: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                                debugAddrFromTag(meta.tag, set), set, meta.wordValid, line));
            end
            else if (!writeBackCache())
            begin
                // Send all writes to backing storage if in write-through mode.
                Vector#(nWordsPerLine, Bool) mask = replicate(False);
                mask[wReq.wordIdx] = True;
                Vector#(nWordsPerLine, t_CACHE_WORD) val = replicate(w_data);
                sourceData.write(cacheAddr(tag, set), mask, unpack(pack(val)));
                debugLog.record($format("  WRITE Through Word: addr=0x%x, wordIdx=%0d, data=0x%x", 
                                debugAddrFromTag(tag, set), wReq.wordIdx, w_data));
            end
        end
        
        // Mark line dirty and word valid
        new_meta.wordValid[wReq.wordIdx] = True;
        new_meta.dirty = writeBackCache();
        metaStore.write(set, new_meta);
        
        // Write word to dataStore
        dataStore[wReq.wordIdx].write(set, w_data);
        debugLog.record($format("  WRITE Word: addr=0x%x, set=0x%x, wordIdx=%0d, newMask=0x%x, data=0x%x", 
                        debugAddrFromTag(tag, set), set, wReq.wordIdx, new_meta.wordValid, w_data));
        doneQ.enq(set);
    endrule

    
    // ====================================================================
    //
    // Fill Path
    //
    // ====================================================================
    
    //
    // fillReq --
    //     Request fill from backing storage.
    //
    (* conservative_implicit_conditions *)
    rule fillReq (True);
        match {.req_base, .maf_idx, .rReq, .mask, .dirty} = fillReqQ.first();
        fillReqQ.deq();
        readMissW.wset(rReq.readMeta);
        let addr = cacheAddr(req_base.tag, req_base.set);
        let word_valid_mask = fromMaybe(replicate(False), mask);
        mafTable.write(maf_idx, tuple4(rReq.readMeta, rReq.wordIdx, word_valid_mask, dirty));
        sourceData.readReq(addr, maf_idx, rReq.globalReadMeta);
        debugLog.record($format("  READ %s MISS (FILL): addr=0x%x, set=0x%x, maf_idx=%0d", 
                        isValid(mask)? "WORD" : "LINE", 
                        debugAddr(addr), req_base.set, maf_idx));
    endrule

    //
    // recvFillResp --
    //     receive fill response from next level memory
    //
    rule handleFillForRead (True);
        let rsp <- sourceData.readResp();
        match {.tag, .set} = cacheTagAndSet(rsp.addr);

        t_CACHE_REQ_BASE req_base;
        req_base.tag = tag;
        req_base.set = set;
        
        mafTable.readReq(rsp.readMeta);
        mafLookupQ.enq(tuple5(req_base, rsp.val, rsp.globalReadMeta, rsp.readMeta, rsp.isCacheable));
    endrule

    //
    // handleFillForCacheableRead --
    //    Update the cache with requested data coming back from memory.
    //
    rule handleFillForCacheableRead (tpl_5(mafLookupQ.first()));
        //
        // Cache the new values.  Don't overwrite entries that are currently
        // valid, since they may be dirty.
        //
        // On return only claim that the newly filled words are valid.
        //
        let maf_data <- mafTable.readRsp();
        match {.client_meta, .word_idx, .cur_word_valid_mask, .cur_meta_dirty} = maf_data;
        match {.req_base, .val, .global_read_meta, .maf_idx, .is_cacheable} = mafLookupQ.first();
        mafLookupQ.deq();
        mafTable.free(maf_idx);

        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));
        
        let tag = req_base.tag;
        let set = req_base.set;
        
        cacheLineDataWrite(set, ret_valid_words, val);

        let r_req = RL_SA_BRAM_CACHE_READ_REQ { wordIdx: word_idx, 
                                                readMeta: client_meta, 
                                                globalReadMeta: global_read_meta };

        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         r_req,
                                         val,
                                         ret_valid_words,
                                         is_cacheable));

        debugLog.record($format("  Read FILL: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x",
                                debugAddrFromTag(tag, set), set, ret_valid_words, val));
        doneQ.enq(req_base.set);
    endrule

    //
    // handleFillForUncacheableRead --
    //
    rule handleFillForUncacheableRead (!tpl_5(mafLookupQ.first()));
        //
        // On return only claim that the newly filled words are valid.
        //
        let maf_data <- mafTable.readRsp();
        match {.client_meta, .word_idx, .cur_word_valid_mask, .cur_meta_dirty} = maf_data;
        match {.req_base, .val, .global_read_meta, .maf_idx, .is_cacheable} = mafLookupQ.first();
        mafLookupQ.deq();
        mafTable.free(maf_idx);

        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));

        let r_req = RL_SA_BRAM_CACHE_READ_REQ { wordIdx: word_idx, 
                                                readMeta: client_meta, 
                                                globalReadMeta: global_read_meta };
        let tag = req_base.tag;
        let set = req_base.set;
       
        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         r_req,
                                         val,
                                         ret_valid_words,
                                         is_cacheable));

        debugLog.record($format("  Read FILL [NOT CACHEABLE]: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x",
                        debugAddrFromTag(tag, set), set, ret_valid_words, val));
        //
        // Abnormal path.  Response is uncacheable.  The line has already been 
        // marked valid in anticipation of the response, so the metadata must 
        // now be fixed.
        metaStore.write(set, RL_MW_DM_CACHE_METADATA{tag: tag, dirty: cur_meta_dirty, wordValid: cur_word_valid_mask});
        doneQ.enq(set);
    endrule

    // ====================================================================
    //
    //   End of reference.
    //
    // ====================================================================

    // BE CAREFUL HERE!  Poor choice of order can cause deadlocks.
    (* descending_urgency = "doneWithRef, handleFillForRead, handleFillForCacheableRead, handleFillForUncacheableRead, fillReq, pickReqQueue, fwdInvalOrFlush, handleRead, handleWrite, handleInvalOrFlush" *)

    //
    // doneWithRef --
    //     All access paths terminate here.
    //
    rule doneWithRef (True);
        let set = doneQ.first();
        doneQ.deq();
        setFilterRemoveW.send();
        setFilter.remove(set);
    endrule

    // ====================================================================
    //
    //   Debug scan state
    //
    // ====================================================================

    List#(Tuple2#(String, Bool)) ds_data = List::nil;

    ds_data = List::cons(tuple2("SA BRAM Cache newReqQ NotEmpty", newReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache cacheLookupQ NotEmpty", cacheLookupQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache fillReqQ NotEmpty", fillReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache mafLookupQ NotEmpty", mafLookupQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache doneQ NotEmpty", doneQ.notEmpty), ds_data);

    let debugScanData = ds_data;
    
    // ====================================================================
    //
    //   Incoming cache requests (methods)
    //
    // ====================================================================

    //
    // genRequest --
    //     This function is used by most of the request methods to generate
    //     the internal data structure for managing a request.  It also starts
    //     the first step:  reading metadata from BRAM.
    //
    function ActionValue#(t_CACHE_SET_IDX) genRequest(t_CACHE_REQ req,
                                                      t_CACHE_ADDR addr);
        actionvalue
            match {.tag, .set} = cacheTagAndSet(addr);

            t_CACHE_REQ_BASE req_base;
            req_base.tag = tag;
            req_base.set = set;
            newReqQ.enq(tuple2(req_base, req));
            
            return set;
        endactionvalue
    endfunction

    //
    // readReq -- Read up to a full line.  Fetch from backing store if not in the cache.
    //
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

        RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META) req;
        req.wordIdx = wordIdx;
        req.readMeta = readMeta;
        req.globalReadMeta = globalReadMeta;
        
        let set <- genRequest(tagged HCOP_READ req, addr);
        debugLog.record($format("  New request: READ addr=0x%x, set=0x%x, word=%0d", debugAddr(addr), set, wordIdx));
    endmethod

    method ActionValue#(t_CACHE_LOAD_RESP) readResp();
        match {.req_base, .r_req, .v, .valid_words, .is_cacheable} = readRespToClientQ_OOO.first();
        readRespToClientQ_OOO.deq();
        Vector#(nWordsPerLine, t_CACHE_WORD) value = unpack(pack(v));

        t_CACHE_LOAD_RESP rsp;
        for (Integer w = 0; w < valueOf(nWordsPerLine); w = w + 1)
            rsp.words[w] = valid_words[w] ? tagged Valid value[w] : tagged Invalid;
        rsp.addr = cacheAddr(req_base.tag, req_base.set);
        rsp.reqWordIdx = r_req.wordIdx;
        rsp.isCacheable = is_cacheable;
        rsp.readMeta = r_req.readMeta;
        rsp.globalReadMeta = r_req.globalReadMeta;

        return rsp;
    endmethod

    method t_CACHE_ADDR peekRespAddr();
        match {.req_base, .r_req, .v, .valid_words} = readRespToClientQ_OOO.first();
        return cacheAddr(req_base.tag, req_base.set);
    endmethod

    method Bool readRespReady();
        return readRespToClientQ_OOO.notEmpty();
    endmethod

    //
    // write -- Write a word to a line.
    //
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_WORD_IDX wordIdx);
        let h <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(h, val);

        RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine) w_req;
        w_req.wordIdx = wordIdx;    
        w_req.dataIdx = h;

        let set <- genRequest(tagged HCOP_WRITE w_req, addr);

        debugLog.record($format("  New request: WRITE addr=0x%x, set=0x%x, data=0x%x, word=%0d, wData heap=%0d", debugAddr(addr), set, val, wordIdx, h));
    endmethod


    //
    // invalReq -- Invalidate (remove) a line from the cache
    //
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        let set <- genRequest(tagged HCOP_INVAL sendAck, addr);
        debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x, needAck=%s", 
                        debugAddr(addr), set, sendAck? "True" : "False"));
    endmethod
    

    //
    // flushReq --
    //     Flush (write back) a line from the cache but keep the line cached.
    //
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        let set <- genRequest(tagged HCOP_FLUSH_DIRTY sendAck, addr);
        debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x, needAck=%s", 
                        debugAddr(addr), set, sendAck? "True" : "False"));
    endmethod

    //
    // invalOrFlushWait -- Block until an inval or flush request completes.
    //
    method Action invalOrFlushWait();
        debugLog.record($format("    INVAL/FLUSH complete"));
        sourceData.invalOrFlushWait();
    endmethod

    //
    // setCacheMode -- Configure cache behavior.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
        if (cacheMode != mode)
        begin
            debugLog.record($format("Cache mode: %0d", mode));
        end
        cacheMode <= mode;    
    endmethod

    //
    // debugScanState -- Return cache state for DEBUG_SCAN.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
        return debugScanData;
    endmethod

    interface RL_CACHE_STATS stats;
        method readHit = readHitW.wget;
        method readMiss = readMissW.wget;
        method readRecentLineHit = False;
        method writeHit = writeHitW.wget;
        method writeMiss = writeMissW.wget;
        method newMRU = False;
        method invalEntry = invalEntryW;
        method dirtyEntryFlush = dirtyEntryFlushW;
        method forceInvalLine = forceInvalLineW;
        method entryAccesses = ?;
    endinterface

endmodule


// ===================================================================
//
// Real set associative cache implementation
//
// ===================================================================

//
// Basic request information constructed when a new request arrives.
//
typedef struct
{
    t_CACHE_TAG     tag;
    t_CACHE_SET_IDX set;
    t_CACHE_WAY_IDX way;
}
RL_SA_BRAM_CACHE_REQ_BASE#(type t_CACHE_TAG,
                           type t_CACHE_SET_IDX,
                           type t_CACHE_WAY_IDX)
    deriving(Bits, Eq);

typedef enum
{
    RL_SA_BRAM_CACHE_DATA_READ_HIT,
    RL_SA_BRAM_CACHE_DATA_FLUSH, 
    RL_SA_BRAM_CACHE_DATA_MISS
}
RL_SA_BRAM_CACHE_DATA_LOOKUP_TYPE
    deriving (Eq, Bits);

//
// Specify read client for cache meta reads.
//
typedef enum
{
    RL_SA_BRAM_CACHE_META_CLIENT_STD,
    RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE,
    RL_SA_BRAM_CACHE_META_CLIENT_INVALID
}
RL_SA_BRAM_CACHE_META_CLIENT
    deriving (Eq, Bits);


//
// Cache set metadata includes LRU chain and the metadata for each way.  The
// way metadata is wrapped in a Maybe#() to permit invalid (unallocated) ways.
//
typedef struct
{
    Vector#(nWays, UInt#(t_CACHE_WAY_IDX_SZ)) lru;
    Vector#(nWays, Maybe#(RL_SA_CACHE_WAY_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets))) ways;
}
RL_SA_BRAM_CACHE_SET_METADATA#(numeric type t_CACHE_WAY_IDX_SZ, 
                               numeric type t_CACHE_ADDR_SZ, 
                               numeric type nWordsPerLine,
                               numeric type nSets, 
                               numeric type nWays)
    deriving(Bits, Eq);

instance DefaultValue#(RL_SA_BRAM_CACHE_SET_METADATA#(t_CACHE_WAY_IDX_SZ, t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays));
    defaultValue = RL_SA_BRAM_CACHE_SET_METADATA { lru: Vector::genWith(fromInteger),
                                                   ways: Vector::replicate(tagged Invalid)
                                                 };
endinstance


//
// mkCacheSetAssocWithBRAMImpl --
//    Set associative cache implemented with BRAM.
//
module mkCacheSetAssocWithBRAMImpl#(RL_SA_BRAM_CACHE_SOURCE_DATA#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_LINE, nWordsPerLine, t_MAF_IDX) sourceData,
                                    NumTypeParam#(nSets) param0,
                                    NumTypeParam#(nWays) param1,
                                    NumTypeParam#(nTagExtraLowBits) param2,
                                    DEBUG_FILE debugLog)
    // interface:
        (RL_SA_BRAM_CACHE#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META))
    provisos (Bits#(t_CACHE_LINE, t_CACHE_LINE_SZ),
              Bits#(t_CACHE_READ_META, t_CACHE_READ_META_SZ),
              Bits#(t_CACHE_WORD, t_CACHE_WORD_SZ),

              // Write word size must tile into cache line
              Bits#(Vector#(nWordsPerLine, t_CACHE_WORD), t_CACHE_LINE_SZ),

              // Cache address size must be no larger than 128 bits because
              // of the hash function.
              Add#(t_CACHE_ADDR_SZ, a__, 128),

              // Set index and tag.  Set index size + tag size == address size.
              Alias#(RL_SA_CACHE_SET_IDX#(nSets), t_CACHE_SET_IDX),
              Bits#(t_CACHE_SET_IDX, t_CACHE_SET_IDX_SZ),
              Alias#(RL_SA_CACHE_TAG#(t_CACHE_ADDR_SZ, nSets), t_CACHE_TAG),

              // Set size must be no longer than 32 bits (for set filter)
              Add#(t_CACHE_SET_IDX_SZ, b__, 32),

              Alias#(Bit#(t_CACHE_ADDR_SZ), t_CACHE_ADDR),
              NumAlias#(TMax#(TLog#(nWays), 1), t_CACHE_WAY_IDX_SZ),
              Alias#(UInt#(t_CACHE_WAY_IDX_SZ), t_CACHE_WAY_IDX),
              Alias#(UInt#(TAdd#(t_CACHE_SET_IDX_SZ, TLog#(nWays))), t_CACHE_DATA_IDX),
              Alias#(RL_SA_CACHE_WAY_METADATA#(t_CACHE_ADDR_SZ, nWordsPerLine, nSets), t_METADATA),
              Alias#(RL_SA_CACHE_LOAD_RESP#(t_CACHE_ADDR, t_CACHE_WORD, nWordsPerLine, t_CACHE_READ_META), t_CACHE_LOAD_RESP),
              Alias#(Vector#(nWays, t_CACHE_WAY_IDX), t_LRU_LIST),
              Alias#(Vector#(nWays, Maybe#(t_METADATA)), t_METADATA_VECTOR),
              Alias#(RL_SA_BRAM_CACHE_SET_METADATA#(t_CACHE_WAY_IDX_SZ, t_CACHE_ADDR_SZ, nWordsPerLine, nSets, nWays), t_SET_METADATA),
              Alias#(RL_SA_BRAM_CACHE_REQ_BASE#(t_CACHE_TAG, t_CACHE_SET_IDX, t_CACHE_WAY_IDX), t_CACHE_REQ_BASE),
              Alias#(RL_SA_BRAM_CACHE_REQ#(nWordsPerLine, t_CACHE_READ_META), t_CACHE_REQ),
              Alias#(Bit#(TLog#(nWordsPerLine)), t_CACHE_WORD_IDX),
              Alias#(RL_SA_CACHE_WRITE_INFO#(t_CACHE_WORD, t_CACHE_WORD_IDX), t_CACHE_WRITE_INFO),
              Alias#(Vector#(nWordsPerLine, Bool), t_CACHE_WORD_VALID_MASK),
       
              Bits#(t_CACHE_REQ, t_CACHE_REQ_SZ),

              Alias#(Bit#(TLog#(RL_SA_BRAM_CACHE_MAF_ENTRIES)), t_MAF_IDX),

              // Unbelievably ugly tautologies required by the compiler:
              Add#(TSub#(t_CACHE_ADDR_SZ, TLog#(nSets)), TLog#(nSets), t_CACHE_ADDR_SZ),
              Add#(t_CACHE_ADDR_SZ, nTagExtraLowBits, TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)),
              Log#(nWays, TLog#(nWays)),
              Add#(TLog#(TExp#(TLog#(nSets))), 0, TLog#(nSets)),
              Add#(TLog#(TDiv#(TExp#(TLog#(nSets)), 2)), x__, TLog#(nSets)));

    // Set a safe increment value for the access histogram stats
    // tracker.  If this feature is disabled, the tracker width will
    // be zero, and the increment value must also be zero. 
    UInt#(TAdd#(1,`RL_CACHE_LINE_ACCESS_TRACKER_WIDTH)) accessIncrementValueLarge = 1;
    UInt#(`RL_CACHE_LINE_ACCESS_TRACKER_WIDTH) accessIncrementValue = truncate(accessIncrementValueLarge);

    // ***** Elaboration time checks of types
    // The interface allows for a number of sets that isn't a
    // power of 2, but the implementation currently does not.
    if(valueof(nSets) != valueof(TExp#(TLog#(nSets))))
    begin
        error("nSets must be a power of 2");
    end
    
    // Cache Storage
    
    // Metadata
    BRAM#(RL_SA_CACHE_SET_IDX#(nSets), t_SET_METADATA) metaStore = ?; 
    
    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        metaStore <- mkBRAMInitialized(defaultValue);
    end
    else if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 1)
    begin
        // Cache implemented as 4 BRAM banks with I/O buffering to allow
        // more time to reach memory.
        NumTypeParam#(4) p_banks = ?;
        metaStore <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                     mkBRAMInitializedBuffered(defaultValue));
    end
    else
    begin
        // Cache implemented as 4 half-speed BRAM banks.
        NumTypeParam#(4) p_banks = ?;

        // Add buffering.  This accomplishes two things:
        //   1. It adds a fully scheduled stage (without conservative conditions)
        //      that allows requests to go to banks that aren't busy.
        //   2. Buffering supports long wires.
        let meta_slow = mkSlowMemoryM(mkBRAMInitializedClockDivider(defaultValue), True);
        metaStore <- mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW, meta_slow);
    end

    // Values
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z    
    Vector#(TMul#(nWordsPerLine, nWays), BRAM#(t_CACHE_SET_IDX, t_CACHE_WORD)) dataStore = ?;
    FIFOF#(t_CACHE_LINE) dataStoreRspQ = ?;
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
    FIFOF#(Maybe#(t_CACHE_WAY_IDX)) dataStoreLookupInfoQ = ?;
`else
    FIFOF#(t_CACHE_WAY_IDX) dataStoreLookupInfoQ = ?;
`endif

    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        dataStore <- replicateM(mkBRAMSized(valueof(nSets)));
        dataStoreRspQ <- mkFIFOF();
        dataStoreLookupInfoQ <- mkFIFOF();
    end
    else if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 1)
    begin
        NumTypeParam#(4) p_banks = ?;
        dataStore <- replicateM(mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                                mkBRAMSizedBuffered(valueof(nSets)/4)));
        dataStoreRspQ <- mkSizedFIFOF(4);
        dataStoreLookupInfoQ <- mkSizedFIFOF(4);
    end
    else
    begin
        NumTypeParam#(4) p_banks = ?;
        let data_slow = mkSlowMemoryM(mkBRAMSizedClockDivider(valueof(nSets)/4), True);
        dataStore <- replicateM(mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW, data_slow));
        dataStoreRspQ <- mkSizedFIFOF(4);
        dataStoreLookupInfoQ <- mkSizedFIFOF(4);
    end
`else    
    Vector#(nWordsPerLine, BRAM#(t_CACHE_DATA_IDX, t_CACHE_WORD)) dataStore = ?;

    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        dataStore <- replicateM(mkBRAMSized(valueof(nSets)*valueof(nWays)));
    end
    else if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 1)
    begin
        NumTypeParam#(4) p_banks = ?;
        dataStore <- replicateM(mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW,
                                                mkBRAMSizedBuffered(valueof(nSets)*valueof(nWays)/4)));
    end
    else
    begin
        NumTypeParam#(4) p_banks = ?;
        let data_slow = mkSlowMemoryM(mkBRAMSizedClockDivider(valueof(nSets)*valueof(nWays)/4), True);
        dataStore <- replicateM(mkBankedMemoryM(p_banks, MEM_BANK_SELECTOR_BITS_LOW, data_slow));
    end
`endif

    // ***** Internal state *****

    // Write data is kept in a heap to avoid passing it around through FIFOs.
    // The heap size limits the number of writes in flight.
    MEMORY_HEAP_IMM#(Bit#(WRITE_DATA_HEAP_IDX_SZ), t_CACHE_WRITE_INFO) reqInfo_writeData <- mkMemoryHeapLUTRAM();
    MEMORY_HEAP#(t_MAF_IDX,Tuple4#(t_CACHE_READ_META, t_CACHE_WORD_IDX, t_CACHE_WORD_VALID_MASK, t_CACHE_WAY_IDX)) mafTable <- mkMemoryHeapUnionBRAM();

    // Is the cache write back?  If not, never set a dirty bit.  It is then the
    // responsibility of the caller to write values to backing storage.
    Reg#(RL_SA_CACHE_MODE) cacheMode <- mkReg(RL_SA_MODE_WRITE_BACK);
    function Bool writeBackCache() = (cacheMode == RL_SA_MODE_WRITE_BACK);
    function Bool cacheEnabled() = (pack(cacheMode)[1] == 0);

    // Filter for allowing one live operation per cache set.
    COUNTING_FILTER#(t_CACHE_SET_IDX, 1) setFilter <- mkCountingFilter(debugLog);

    // ***** Queues between internal pipeline stages *****

    // Incoming requests
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) newReqQ <- mkFIFOF();
    // Cache meta lookup queue
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, RL_SA_BRAM_CACHE_META_CLIENT)) metaLookupQ = ?;
    // Cache data lookup queue
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK, RL_SA_BRAM_CACHE_DATA_LOOKUP_TYPE)) dataLookupQ = ?;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_SET_METADATA, Bool)) metaProcessQ = ?;
`endif

    // Queues on miss path
    FIFOF#(Tuple3#(t_SET_METADATA, t_CACHE_WAY_IDX, t_MAF_IDX)) lineMissQ = ?;
    FIFOF#(Tuple4#(t_CACHE_REQ_BASE, t_CACHE_REQ, t_CACHE_WORD_VALID_MASK, t_MAF_IDX)) wordMissQ <- mkFIFOF();

    // Fill for read path
    FIFOF#(Tuple3#(t_CACHE_REQ_BASE, t_MAF_IDX, RL_CACHE_GLOBAL_READ_META)) fillLineRequestQ <- mkFIFOF();
    FIFOF#(t_CACHE_WORD_VALID_MASK) fillLineUncacheableQ = ?;
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, t_CACHE_LINE, RL_CACHE_GLOBAL_READ_META, t_MAF_IDX, Bool)) mafLookupQ <- mkFIFOF();

    // Write data to an allocated queue entry
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine))) writeDataQ <- mkFIFOF();

    // Inval or flush path
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, Bool)) invalOrFlushQ <- mkFIFOF();

    // Exit from all paths
    FIFOF#(t_CACHE_SET_IDX) doneQ <- mkFIFOF();

    // Read responses may be returned out of order relative to request order!
    FIFOF#(Tuple5#(t_CACHE_REQ_BASE, RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META), t_CACHE_LINE, t_CACHE_WORD_VALID_MASK, Bool)) readRespToClientQ_OOO <- mkFIFOF();

    if (`RL_SA_BRAM_CACHE_BRAM_TYPE == 0)
    begin
        metaLookupQ <- mkFIFOF();
        dataLookupQ <- mkFIFOF();
        lineMissQ   <- mkFIFOF();
        fillLineUncacheableQ <- mkFIFOF();
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        metaProcessQ <- mkFIFOF();
`endif
    end
    else
    begin
        metaLookupQ <- mkSizedFIFOF(4);
        dataLookupQ <- mkSizedFIFOF(4);
        lineMissQ   <- mkSizedFIFOF(4);
        fillLineUncacheableQ <- mkSizedFIFOF(4);
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        metaProcessQ <- mkSizedFIFOF(4);
`endif
    end

    RWire#(t_CACHE_READ_META) readMissW          <- mkRWire();
    RWire#(t_CACHE_READ_META) writeMissW         <- mkRWire();
    RWire#(t_CACHE_READ_META) readHitW           <- mkRWire();
    RWire#(t_CACHE_READ_META) writeHitW          <- mkRWire();
    PulseWire newMRUW            <- mkPulseWire();
    PulseWire invalEntryW        <- mkPulseWire();
    PulseWire forceInvalLineW    <- mkPulseWire();
    PulseWire dirtyEntryFlushW   <- mkPulseWire();

    RWire#(UInt#(`RL_CACHE_LINE_ACCESS_TRACKER_WIDTH)) entryAccessesW  <- mkRWire();

    // ***** Indexing functions *****
    //
    // getDataIdx --
    //     Index in the cache data BRAM given a set and way.
    //
    function t_CACHE_DATA_IDX getDataIdx (t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        t_CACHE_DATA_IDX idx;
        if (valueOf(nWays) == 1)
        begin
            idx = unpack(zeroExtend(pack(set)));
        end
        else
        begin
            Bit#(TLog#(nWays)) wayIdx = truncate(pack(way));
            idx = unpack(pack(tuple2(wayIdx,set)));
        end
        return idx;
    endfunction
    
    //
    // Functions for converting from address to tag and set or vice versa.
    //
    function Tuple2#(t_CACHE_TAG, t_CACHE_SET_IDX) cacheTagAndSet(t_CACHE_ADDR addr);
        return unpack(hashBits(addr));
    endfunction

    function t_CACHE_ADDR cacheAddr(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        t_CACHE_ADDR hashed_addr = { tag, pack(set) };
        return hashBits_inv(hashed_addr);
    endfunction

    //
    // debugAddr --
    //     Pretty printer for converting cache addresses to system addresses.
    //     Adds trailing 0's that were dropped from cache addresses because they
    //     are inside a cache line.
    //
    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddr(t_CACHE_ADDR addr);
        Bit#(nTagExtraLowBits) zero = 0;
        return { addr, zero };
    endfunction

    function Bit#(TAdd#(t_CACHE_ADDR_SZ, nTagExtraLowBits)) debugAddrFromTag(t_CACHE_TAG tag, t_CACHE_SET_IDX set);
        Bit#(nTagExtraLowBits) zero = 0;
        return { cacheAddr(tag, set), zero };
    endfunction


    // ***** Meta data searches *****

    function t_METADATA metaData(t_CACHE_TAG tag,
                                 Bool dirty,
                                 t_CACHE_WORD_VALID_MASK wordValid,
                                 UInt#(`RL_CACHE_LINE_ACCESS_TRACKER_WIDTH) accesses);
        t_METADATA meta;
        meta.tag = tag;
        meta.dirty = dirty;
        meta.wordValid = wordValid;
        meta.accesses = accesses;    

        return meta;
    endfunction


    function Maybe#(Tuple2#(t_CACHE_WAY_IDX, t_METADATA)) findWayMatch(t_CACHE_TAG tag, t_SET_METADATA meta);
        
        Vector#(nWays, Bool) way_match = replicate(False);

        for (Integer w = 0; w < valueOf(nWays); w = w + 1)
        begin
            way_match[w] = case (meta.ways[w]) matches
                               tagged Valid .m: (m.tag == tag);
                               default: False;
                           endcase;
        end
        
        if (valueOf(nWays) == 1)
        begin
            if (cacheEnabled() && way_match[0]) 
                return tagged Valid tuple2(unpack(0), validValue(meta.ways[0]));
            else
                return tagged Invalid;
        end
        else
        begin
            Maybe#(UInt#(TLog#(nWays))) way = findElem(True, way_match);
            if (cacheEnabled() &&& way matches tagged Valid .w)
                return tagged Valid tuple2(unpack(zeroExtend(pack(w))), validValue(meta.ways[w]));
            else
                return tagged Invalid;
        end
    endfunction


    function Bool isInvalid(Maybe#(t) m) = ! isValid(m);


    function Maybe#(t_CACHE_WAY_IDX) findFirstInvalid(t_METADATA_VECTOR meta);
        if (valueOf(nWays) == 1)
        begin
            return isValid(meta[0])? tagged Invalid : tagged Valid unpack(0);
        end
        else
        begin
            Maybe#(UInt#(TLog#(nWays))) idx = findIndex(isInvalid, meta);
            return isValid(idx)? tagged Valid unpack(zeroExtend(pack(validValue(idx)))) : tagged Invalid;
        end
    endfunction


    // ***** LRU Management ***** //

    t_CACHE_WAY_IDX mruIDX = fromInteger(valueOf(TSub#(nWays, 1)));

    //
    // getLRU --
    //   Least recently used way in a set.
    //
    function t_CACHE_WAY_IDX getLRU(t_LRU_LIST list);
        if (valueOf(nWays) == 1)
        begin
            return unpack(0);
        end
        else
        begin
            Bit#(TLog#(nWays)) idx = pack(validValue(findElem(0, list)));
            return unpack(zeroExtend(idx));
        end
    endfunction


    //
    // getMRU --
    //   Most recently used way in a set.
    //

    function t_CACHE_WAY_IDX getMRU(t_LRU_LIST list);
        if (valueOf(nWays) == 1)
        begin
            return unpack(0);
        end
        else
        begin
            Bit#(TLog#(nWays)) idx = pack(validValue(findElem(mruIDX, list)));
            return unpack(zeroExtend(idx));
        end
    endfunction


    //
    // pushMRU --
    //   Update MRU list, moving a way to the head of the list.
    //
    function t_LRU_LIST pushMRU(t_LRU_LIST curLRU, t_CACHE_WAY_IDX mruWay);
        
        if (valueOf(nWays) == 1)
        begin
            return curLRU;
        end
        else
        begin
            UInt#(TLog#(nWays)) mru = unpack(truncate(pack(mruWay)));
            t_CACHE_WAY_IDX cur_priority = curLRU[mru];
            //
            // Shift older references out of the MRU slot
            //
            t_LRU_LIST new_list = newVector();
            
            for (Integer w = 0; w < valueOf(nWays); w = w + 1)
            begin
                if (fromInteger(w) == mru)
                begin
                    new_list[w] = mruIDX;
                end
                else if (curLRU[w] > cur_priority)
                begin
                    new_list[w] = curLRU[w] - 1;
                end
                else
                begin
                    new_list[w] = curLRU[w];
                end
            end

            return new_list;
        end
    endfunction

    function ActionValue#(t_LRU_LIST) cacheLRUUpdate(t_CACHE_SET_IDX set,
                                                     t_CACHE_WAY_IDX way,
                                                     t_LRU_LIST cur_lru);
        actionvalue

        let new_lru = pushMRU(cur_lru, way);

        if ((getMRU(cur_lru) != way) || (cur_lru != new_lru))
        begin
            debugLog.record($format("    Update LRU (set=0x%x): MRU %0d / %b -> %b", set, way, cur_lru, new_lru));
        end
        if (getMRU(new_lru) != way)
        begin
            debugLog.record($format("    ***ERROR*** expected MRU to be 0x%x but it is 0x%x", way, getMRU(new_lru)));
        end

        return new_lru;
        endactionvalue
    endfunction

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
    function Action cacheLineDataPrefetch(t_CACHE_SET_IDX set);
        action
            for (Integer b = 0; b < valueOf(nWordsPerLine)*valueOf(nWays); b = b + 1)
            begin
                dataStore[b].readReq(set);
                debugLog.record($format("  cacheLineDataPrefetch: set=0x%x, dataStoreIdx=%0d", set, b));
            end
        endaction
    endfunction
    function Action cacheLineDataReadReqInvalid();
        action
            dataStoreLookupInfoQ.enq(tagged Invalid);
            debugLog.record($format("  cacheLineDataReadReqInvalid: data prefetch is invalid"));
        endaction
    endfunction
    function Action cacheLineDataRespDrop();
        action
            for (Integer b = 0; b < valueOf(nWordsPerLine)*valueOf(nWays); b = b + 1)
            begin
                let d <- dataStore[b].readRsp();
                debugLog.record($format("  cacheLineDataRespDrop: dataStoreIdx=%0d", b));
            end
        endaction
    endfunction
`endif
`endif

    // cache access functions
    function Action cacheLineDataReadReq(t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way);
        action
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
    `ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
            dataStoreLookupInfoQ.enq(tagged Valid way);
    `else
            Tuple2#(t_CACHE_WAY_IDX, Bit#(TLog#(nWordsPerLine))) data_store_idx = tuple2(way, 0);
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                let idx = pack(data_store_idx) + fromInteger(b);
                dataStore[idx].readReq(set);
                debugLog.record($format("  cacheLineDataReadReq: set=0x%x, way=%0d, dataStoreIdx=%0d", set, way, idx));
            end
            dataStoreLookupInfoQ.enq(way);
    `endif            
`else            
            let data_idx = getDataIdx(set, way); 
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                dataStore[b].readReq(data_idx);
            end
`endif
        endaction
    endfunction
    
    function Action cacheLineDataWrite(t_CACHE_SET_IDX set, t_CACHE_WAY_IDX way, t_CACHE_WORD_VALID_MASK mask, t_CACHE_LINE val);
        action
            Vector#(nWordsPerLine, t_CACHE_WORD) words = unpack(pack(val));
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
            Tuple2#(t_CACHE_WAY_IDX, Bit#(TLog#(nWordsPerLine))) data_store_idx = tuple2(way, 0);
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                if (mask[b])
                begin
                    let idx = pack(data_store_idx) + fromInteger(b);
                    dataStore[idx].write(set, words[b]);
                    debugLog.record($format("  cacheLineDataWrite: set=0x%x, way=%0d, dataStoreIdx=%0d", set, way, idx));
                end
            end
`else            
            let data_idx = getDataIdx(set, way); 
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                if (mask[b])
                begin
                    dataStore[b].write(data_idx, words[b]);
                end
            end
`endif            
        endaction
    endfunction

    function ActionValue#(t_CACHE_LINE) getCacheLineDataResp();
        actionvalue
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z       
            let line_data = dataStoreRspQ.first();
            dataStoreRspQ.deq();
`else            
            Vector#(nWordsPerLine, t_CACHE_WORD) v = newVector();
            for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
            begin
                let d <- dataStore[b].readRsp();
                v[b] = d;
            end
            t_CACHE_LINE line_data = unpack(pack(v));
`endif            
            return line_data;
        endactionvalue
    endfunction
            
            

    // ***** Rules ***** //

    // ====================================================================
    //
    // All incoming requests start here with handleIncomingReq
    //
    // ====================================================================

    //
    // Maintain a side buffer of requests to cache sets that already have
    // in-flight conflicting requests.  This allows non-conflicting requests
    // to proceed.
    //
    FIFOF#(Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ)) sideReqQ <-
        mkSizedFIFOF(valueOf(RL_SA_CONFLICTQ_ENTRIES));

    // A very simple filter to detect lines with requests already in the side
    // cache.
    LUTRAM#(Bit#(6), Bit#(3)) sideReqFilter <- mkLUTRAM(0);
    Reg#(Bit#(1)) newReqArb <- mkReg(0);
    Wire#(Tuple3#(Bool,
                  Tuple2#(t_CACHE_REQ_BASE, t_CACHE_REQ),
                  Maybe#(CF_OPAQUE#(t_CACHE_SET_IDX, 1)))) curReq <- mkWire();
    
    // Track whether the heads of newReqQ and sideReqQ are blocked.  
    // Once blocked, a queue stays blocked until either the head is removed or 
    // a cache index is unlocked when an in-flight request is completed.
    Reg#(Bool) newReqNotBlocked      <- mkConfigReg(True);
    Reg#(Bool) retryReqNotBlocked    <- mkConfigReg(True);
    PulseWire  startSideReqW         <- mkPulseWire();
    PulseWire  setFilterRemoveW      <- mkPulseWire();

    RWire#(Tuple3#(t_CACHE_REQ_BASE, t_CACHE_REQ, RL_SA_BRAM_CACHE_META_CLIENT)) metaLookupReqW <- mkRWire();
    PulseWire metaLookupReqValidW <- mkPulseWire();

    //
    // pickReqQ --
    //     Decide whether to consider the new request or side request queue
    //     this cycle.  Filtering both is too expensive.
    //
    rule pickReqQueue (metaLookupQ.notFull());
        // New requests win over side requests if there is a new request
        // and the arbiter is non-zero.  If the arbitration counter newReqArb
        // is larger than 1 bit this favors new requests over side-buffer
        // requests in an effort to have as many requests in flight as possible.
        Bool new_req_avail = newReqQ.notEmpty && newReqNotBlocked;
        Bool side_req_avail = sideReqQ.notEmpty && retryReqNotBlocked;
        Bool pick_new_req = new_req_avail && ((newReqArb != 0) || !side_req_avail);
    
        let r = pick_new_req ? newReqQ.first() : sideReqQ.first();

        match {.req_base, .req} = r;
        let tag = req_base.tag;
        let set = req_base.set;
        
        // speculatively read meta data and LRU hints
        metaStore.readReq(req_base.set);
        metaLookupReqW.wset(tuple3(req_base, req, RL_SA_BRAM_CACHE_META_CLIENT_STD));
        newReqArb <= newReqArb + 1;

        // In order to preserve read/write and write/write order, the
        // request must either come from the side buffer or be a new request
        // referencing a line not already in the side buffer.
        //
        // The array sideReqFilter tracks lines active in the side request
        // queue.
        if (! pick_new_req || sideReqFilter.sub(resize(set)) == 0)
        begin
            curReq <= tuple3(pick_new_req, r, setFilter.test(set));
        end
        else
        begin
            curReq <= tuple3(pick_new_req, r, tagged Invalid);
        end
    endrule

    //
    // startReq --
    //     Start the current request if the line is not busy.
    //
    (* fire_when_enabled *)
    rule startReq (tpl_3(curReq) matches tagged Valid .filter_state);
        match {.pick_new_req, .r, .cf_opaque} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        setFilter.set(filter_state);

        metaLookupReqValidW.send();

        debugLog.record($format("  FWD %s to ReqQ: addr=0x%x, set=0x%x",
                                pick_new_req ? "new" : "side",
                                debugAddrFromTag(tag, set), set));

        if (pick_new_req)
        begin
            newReqQ.deq();
        end
        else
        begin
            sideReqQ.deq();
            startSideReqW.send();
            sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) - 1);
        end
    endrule

    //
    // shuntNewReq --
    //     If the current request is new (not a shunted request) and the
    //     line is busy, shunt the new request to a side queue in order to
    //     attempt to process a later request that may be ready to go.
    //
    //     This rule will not fire if startReq fires.
    //
    match {.curReq_req_base, .curReq_req} = tpl_2(curReq);
    
    function Bool isOrderedReq(t_CACHE_REQ req);
        if (req matches tagged HCOP_READ .rReq &&& rReq.globalReadMeta.orderedSourceDataReqs == True)
            return True;
        else
            return False;
    endfunction

    (* fire_when_enabled *)
    rule shuntNewReq (tpl_1(curReq) &&
                      ! isOrderedReq(curReq_req) &&
                      (sideReqFilter.sub(resize(curReq_req_base.set)) != maxBound) &&
                      ! isValid(tpl_3(curReq)) &&
                      cacheEnabled);
        match {.pick_new_req, .r, .cf_opaque} = curReq;
        match {.req_base, .req} = r;

        let tag = req_base.tag;
        let set = req_base.set;

        debugLog.record($format("  SIDE shunt req: addr=0x%x, set=0x%x",
                                debugAddrFromTag(tag, set), set));

        sideReqQ.enq(r);
        newReqQ.deq();

        // Note line present in sideReqQ
        sideReqFilter.upd(resize(set), sideReqFilter.sub(resize(set)) + 1);
    endrule
    
    //
    // blockNewReq --
    //     Check if the head of newReqQ is blocked by busy cache lines and 
    // cannot be shunt to retry queue. 
    //
    (* fire_when_enabled *)
    rule blockNewReq (tpl_1(curReq) && ( isOrderedReq(curReq_req) || 
                      (sideReqFilter.sub(resize(curReq_req_base.set)) == maxBound) || cacheEnabled ) &&
                      ! isValid(tpl_3(curReq)));
        newReqNotBlocked <= False;
        debugLog.record($format("  New req blocked by busy: addr=0x%x", 
                        debugAddrFromTag(curReq_req_base.tag, curReq_req_base.set)));
    endrule
    
    //
    // unblockLocalReq --
    //     Unblock newReqQ when a sideReq is processed or an inflight request is complete. 
    //
    (* fire_when_enabled *)
    rule unblockNewReq (startSideReqW || setFilterRemoveW);
        newReqNotBlocked <= True;
        debugLog.record($format("  Unblock newReqQ"));
    endrule
    
    //
    // blockSideReq --
    //     Check if the head of the sideReqQ is blocked by busy cache lines.
    //
    (* fire_when_enabled *)
    rule blockSideReq (!tpl_1(curReq) && ! isValid(tpl_3(curReq)));
        retryReqNotBlocked <= False;
        debugLog.record($format("  Side req blocked by busy: addr=0x%x",
                        debugAddrFromTag(curReq_req_base.tag, curReq_req_base.set)));
    endrule
    
    //
    // unblockSideReq --
    //     Unblock the sideReqQ when an inflight request is complete. 
    //
    (* fire_when_enabled *)
    rule unblockLocalRetryReq (setFilterRemoveW);
        retryReqNotBlocked <= True;
        debugLog.record($format("  Unblock sideReqQ"));
    endrule
    
    //
    // Write metaLookupQ to indicate whether a new request was started
    //
    (* fire_when_enabled *)
    rule checkMetaLookup (metaLookupReqW.wget() matches tagged Valid .lookup_req);
        // Was a valid new request started?
        match {.req_base, .req, .lookup_type} = lookup_req;
        if (lookup_type == RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE || metaLookupReqValidW)
        begin
            metaLookupQ.enq(lookup_req);
        end
        else
        begin
            metaLookupQ.enq(tuple3(?, ?, RL_SA_BRAM_CACHE_META_CLIENT_INVALID));
        end
    endrule

    // drop invalid meta lookup
    rule drainMetaRead (tpl_3(metaLookupQ.first) == RL_SA_BRAM_CACHE_META_CLIENT_INVALID);
        metaLookupQ.deq();
        let cur_meta <- metaStore.readRsp();
    endrule
    

    // ======================================================================
    //
    // Pipelined meta processing if RL_SA_BRAM_CACHE_PIPELINE_EN is enabled.
    // Determine whether there is a way match and partially claculate the lru 
    // list in the first stage.   
    //
    // ======================================================================

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule cacheMetaLookup (tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD);
        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;
        let req_base_out = req_base_in;
       
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
        cacheLineDataPrefetch(set);
`endif
        debugLog.record($format("  cacheMetaLookup: addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));
        
        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            req_base_out.way = way;
            metaProcessQ.enq(tuple4(req_base_out, req, meta, True));
            debugLog.record($format("  cacheMetaLookup: find matched way=%0d", way));
        end
        else
        begin
            metaProcessQ.enq(tuple4(req_base_out, req, meta, False));
        end
        
    endrule
            
    
    // Pipelined data store response if RL_SA_BRAM_CACHE_PIPELINE_EN is enabled.
    rule cacheDataLookup (dataStoreLookupInfoQ.notEmpty());
        let lookup_info = dataStoreLookupInfoQ.first();
        dataStoreLookupInfoQ.deq();
        Vector#(nWordsPerLine, t_CACHE_WORD) v = newVector();
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
        if (lookup_info matches tagged Valid .way)
        begin
            Tuple2#(t_CACHE_WAY_IDX, Bit#(TLog#(nWordsPerLine))) data_store_idx_min = tuple2(way, 0);
            Tuple2#(t_CACHE_WAY_IDX, Bit#(TLog#(nWordsPerLine))) data_store_idx_max = tuple2(way, fromInteger(valueOf(nWordsPerLine)-1));
            for (Integer idx = 0; idx < valueOf(nWordsPerLine)*valueOf(nWays); idx = idx + 1)
            begin
                let d <- dataStore[idx].readRsp();
                if ((fromInteger(idx) >= pack(data_store_idx_min)) && (fromInteger(idx) <= pack(data_store_idx_max)))
                begin
                    let b = fromInteger(idx)-pack(data_store_idx_min);
                    v[b] = d;
                    debugLog.record($format("  cacheLineDataResp: way=%0d, dataStoreIdx=%0d, wordIdx=%0d", way, idx, b));
                end
                else
                begin
                    debugLog.record($format("  drop cacheLineDataResp: way=%0d, dataStoreIdx=%0d", way, idx));
                end
            end
            t_CACHE_LINE line_data = unpack(pack(v));
            dataStoreRspQ.enq(line_data);
        end
        else
        begin
            cacheLineDataRespDrop();
        end
`else
        let way = lookup_info;
        Tuple2#(t_CACHE_WAY_IDX, Bit#(TLog#(nWordsPerLine))) data_store_idx = tuple2(way, 0);
        for (Integer b = 0; b < valueOf(nWordsPerLine); b = b + 1)
        begin
            let idx = pack(data_store_idx) + fromInteger(b);
            let d <- dataStore[idx].readRsp();
            v[b] = d;
            debugLog.record($format("  cacheLineDataResp: way=%0d, dataStoreIdx=%0d", way, idx));
        end
        t_CACHE_LINE line_data = unpack(pack(v));
        dataStoreRspQ.enq(line_data);
`endif
    endrule

`endif

    // ====================================================================
    //
    // Two stage path for invalidate or flush requests.  First stage
    // looks up the address in the cache.  If the line is present and dirty,
    // the second stage flushes it to the backing storage.  The third
    // stage responds with an ACK that storage is consistent, if requested.
    //
    // ====================================================================

    function Bool reqIsInvalOrFlush(t_CACHE_REQ req);
        if (req matches tagged HCOP_INVAL .needAck)
            return True;
        else if (req matches tagged HCOP_FLUSH_DIRTY .needAck)
            return True;
        else
            return False;
    endfunction

    //
    // handleInvalOrFlush --
    //     Invalidate and flush requests have similar handling.  Both write
    //     back a dirty matching line.  Flush preserves the now clean line
    //     in the cache.
    //
    (* conservative_implicit_conditions *)
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule handleInvalOrFlush (reqIsInvalOrFlush(tpl_2(metaProcessQ.first())));
        match {.req_base_in, .req, .meta, .way_matched} = metaProcessQ.first();
        metaProcessQ.deq();
`else
    rule handleInvalOrFlush (tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD && reqIsInvalOrFlush(tpl_2(metaLookupQ.first())));
        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();
`endif

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        Bool need_ack = ?;
        Bool is_inval = ?;

        case (req) matches
        tagged HCOP_INVAL .needACK:
        begin
            need_ack = needACK;
            is_inval = True;
            debugLog.record($format("  Process request: INVAL addr=0x%x, set=0x%x, needAck=%s", 
                            debugAddrFromTag(tag, set), set, needACK? "True" : "False"));
        end
        tagged HCOP_FLUSH_DIRTY .needACK:
        begin
            need_ack = needACK;
            is_inval = False;
            debugLog.record($format("  Process request: FLUSH addr=0x%x, set=0x%x, needAck=%s", 
                            debugAddrFromTag(tag, set), set, needACK? "True" : "False"));
        end
        endcase

        Bool found_dirty_line = False;
        let req_base_out = req_base_in;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        if (way_matched)
        begin
            let way = req_base_in.way;
            let way_meta = validValue(meta.ways[way]);
`else
        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            req_base_out.way = way;
`endif
            let meta_upd = meta;

            if (way_meta.dirty)
            begin
                // Found dirty line.  Prepare for write back.
                dataLookupQ.enq(tuple4(req_base_out, req, way_meta.wordValid, RL_SA_BRAM_CACHE_DATA_FLUSH));
                found_dirty_line = True;
                cacheLineDataReadReq(set, way);
                if (! is_inval)
                begin
                    // FLUSH:  Line no longer dirty.  Update meta data.
                    let new_meta = way_meta;
                    new_meta.dirty = False;
                    meta_upd.ways[way] = tagged Valid new_meta;
                end
            end

            if (is_inval)
            begin
                // Invalidate line
                meta_upd.ways[way] = tagged Invalid;
                forceInvalLineW.send();
            end

            metaStore.write(set, meta_upd);
            debugLog.record($format("  FLUSH/INVAL HIT %s: addr=0x%x, set=0x%x, way=%0d", (found_dirty_line ? "dirty" : "clean"), debugAddrFromTag(tag, set), set, way));
        end
        
        if (!found_dirty_line)
        begin
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
            cacheLineDataReadReqInvalid();
`endif
`endif
            if (need_ack)
            begin
                invalOrFlushQ.enq(tuple2(req_base_out, is_inval)); 
            end
            else
            begin
                doneQ.enq(set);
            end
        end
    endrule


    //
    // flushDirtyLine --
    //   Flush a dirty line and continue on to fill, if appropriate.
    //
    (* conservative_implicit_conditions *)
    rule flushDirtyLine (reqIsInvalOrFlush(tpl_2(dataLookupQ.first())));
        match {.req_base, .req, .word_valid_mask, .req_type} = dataLookupQ.first();
        dataLookupQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;
        
        t_CACHE_LINE flush_data <- getCacheLineDataResp();

        dirtyEntryFlushW.send();
        debugLog.record($format("  Write back DIRTY: addr=0x%x, set=0x%x, mask=0x%x, data=0x%x", 
                        debugAddrFromTag(tag, set), set, word_valid_mask, flush_data));

        // Flush for invalidate request.
        sourceData.write(cacheAddr(tag, set), word_valid_mask, flush_data);
        
        if (req matches tagged HCOP_FLUSH_DIRTY .needAck &&& needAck == True)
        begin
            invalOrFlushQ.enq(tuple2(req_base, False));
        end
        else
        begin
            doneQ.enq(set);        
        end
    endrule

    //
    //  fwdInvalOrFlush --
    //    Forward invalidate or flush requests down to next level memory
    //
    rule fwdInvalOrFlush (True);
        match {.req_base, .is_inval} = invalOrFlushQ.first();
        invalOrFlushQ.deq();
        let set = req_base.set;
        let tag = req_base.tag;
        if (is_inval)
        begin
            sourceData.invalReq(cacheAddr(tag, set), True);
        end
        else
        begin
            sourceData.flushReq(cacheAddr(tag, set), True);
        end
        doneQ.enq(set);
    endrule

    // ====================================================================
    //
    // Read and Write data path.
    //
    // ====================================================================

    //
    // handleRead --
    //     First stage of cache READ path.
    //
    (* conservative_implicit_conditions *)
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule handleRead (tpl_2(metaProcessQ.first()) matches tagged HCOP_READ .rReq);
        match {.req_base_in, .req, .meta, .way_matched} = metaProcessQ.first();
        metaProcessQ.deq();
`else
    rule handleRead (tpl_2(metaLookupQ.first()) matches tagged HCOP_READ .rReq &&& tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD);
        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();
`endif

        let tag = req_base_in.tag;
        let set = req_base_in.set;
        
        debugLog.record($format("  Process request: READ addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        Bool need_set_data = False;
        let req_base_out = req_base_in;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        if (way_matched)
        begin
            let way = req_base_in.way;
            let way_meta = validValue(meta.ways[way]);
`else
        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            req_base_out.way = way;
`endif            
            //
            // Line hit!
            //
            // Update LRU
            let meta_upd = meta;
            meta_upd.lru <- cacheLRUUpdate(set, way, meta.lru);

            if (way_meta.wordValid[rReq.wordIdx])
            begin
                // Word hit!
                readHitW.wset(rReq.readMeta);
                need_set_data = True;
                dataLookupQ.enq(tuple4(req_base_out, req, way_meta.wordValid, RL_SA_BRAM_CACHE_DATA_READ_HIT));
                cacheLineDataReadReq(set, way);
                if (meta_upd.lru != meta.lru)
                begin
                    // LRU changed.  Update metadata.
                    metaStore.write(set, meta_upd);
                    newMRUW.send();
                end
            end
            else
            begin
                // Line valid but word in line is not.  Fill.
                let maf_idx <- mafTable.malloc();
                wordMissQ.enq(tuple4(req_base_out, req, way_meta.wordValid, maf_idx));
                // Mark all words valid in the line.  They will be after
                // the fill completes.
                meta_upd.ways[way] = tagged Valid metaData(tag, way_meta.dirty, replicate(True), satPlus(Sat_Bound, way_meta.accesses, accessIncrementValue));
                metaStore.write(set, meta_upd);
                if (meta_upd.lru != meta.lru)
                begin
                    newMRUW.send();
                end
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
                cacheLineDataReadReqInvalid();
`endif
`endif
            end
        end
        else
        begin
            // Miss.
            //
            // Pick a fill victim:  either the first invalid or the LRU entry.
            // 
            t_CACHE_WAY_IDX fill_way = getLRU(meta.lru);
            if (findFirstInvalid(meta.ways) matches tagged Valid .inval_way)
            begin
                fill_way = inval_way;
            end
            let maf_idx <- mafTable.malloc();
            lineMissQ.enq(tuple3(meta, fill_way, maf_idx));
            dataLookupQ.enq(tuple4(req_base_out, req, ?, RL_SA_BRAM_CACHE_DATA_MISS));
            cacheLineDataReadReq(set, fill_way);
        end
    endrule

    //
    // handleWrite --
    //     First unique stage of cache WRITE path.
    //
    (* mutually_exclusive = "handleInvalOrFlush, handleRead, handleWrite" *)
    (* conservative_implicit_conditions *)
`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    rule handleWrite (tpl_2(metaProcessQ.first()) matches tagged HCOP_WRITE .wReq);
        match {.req_base_in, .req, .meta, .way_matched} = metaProcessQ.first();
        metaProcessQ.deq();
`else
    rule handleWrite (tpl_2(metaLookupQ.first()) matches tagged HCOP_WRITE .wReq &&& tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_STD);
        match {.req_base_in, .req, .lookup_type} = metaLookupQ.first();
        metaLookupQ.deq();
        let meta <- metaStore.readRsp();
`endif

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        debugLog.record($format("  Process request: WRITE addr=0x%x, set=0x%x", debugAddrFromTag(tag, set), set));

        let req_base_out = req_base_in;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
        if (way_matched)
        begin
            let way = req_base_in.way;
            let way_meta = validValue(meta.ways[way]);
`else
        if (findWayMatch(tag, meta) matches tagged Valid {.way, .way_meta})
        begin
            req_base_out.way = way;
`endif            
            //
            // Line hit!
            //
            // Update LRU
            let meta_upd = meta;
            meta_upd.lru <- cacheLRUUpdate(set, way, meta.lru);

            writeHitW.wset(?);

            // Mark line dirty and word valid
            let new_word_valid = way_meta.wordValid;
            new_word_valid[wReq.wordIdx] = True;

            meta_upd.ways[way] = tagged Valid metaData(tag, writeBackCache(), new_word_valid, satPlus(Sat_Bound, way_meta.accesses, accessIncrementValue));
            metaStore.write(set, meta_upd);
            
            if (meta_upd.lru != meta.lru)
            begin
                newMRUW.send();
            end

            // Request write to cache
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x", debugAddrFromTag(tag, set), set, way, new_word_valid));

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
`ifndef RL_SA_BRAM_CACHE_PREFETCH_DATA_EN_Z
            cacheLineDataReadReqInvalid();
`endif
`endif
        end
        else
        begin
            // Miss.
            //
            // Pick a fill victim:  either the first invalid or the LRU entry.
            // 
            t_CACHE_WAY_IDX fill_way = getLRU(meta.lru);
            if (findFirstInvalid(meta.ways) matches tagged Valid .inval_way)
            begin
                fill_way = inval_way;
            end
            lineMissQ.enq(tuple3(meta, fill_way, ?));
            dataLookupQ.enq(tuple4(req_base_out, req, ?, RL_SA_BRAM_CACHE_DATA_MISS));
            cacheLineDataReadReq(set, fill_way);
        end
    endrule

    // ====================================================================
    //
    // Read or write hits end here.
    //
    // ====================================================================

    //
    // handleReadCacheHit --
    //   Forward data coming from cache BRAM from handleRead to back to the requester.
    //
    rule handleReadCacheHit (tpl_2(dataLookupQ.first()) matches tagged HCOP_READ .rReq &&& tpl_4(dataLookupQ.first()) == RL_SA_BRAM_CACHE_DATA_READ_HIT);

        match {.req_base, .req, .word_valid_mask, .req_type} = dataLookupQ.first();
        dataLookupQ.deq();
        
        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        t_CACHE_LINE v <- getCacheLineDataResp();
        
        readRespToClientQ_OOO.enq(tuple5(req_base, rReq, v, word_valid_mask, True));

        // Done with this read request
        doneQ.enq(set);

        debugLog.record($format("  Read HIT: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(tag, set), set, way, word_valid_mask, v));
    endrule


    //
    // writeCacheData --
    //   All cache writes terminate here, including the line miss path.
    //
    rule writeCacheData (True);
        match {.req_base, .w_req} = writeDataQ.first();
        writeDataQ.deq();

        let w_data = reqInfo_writeData.sub(w_req.dataIdx);
        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z        
        Tuple2#(t_CACHE_WAY_IDX, Bit#(TLog#(nWordsPerLine))) data_store_idx = tuple2(way, w_req.wordIdx);
        dataStore[pack(data_store_idx)].write(set, w_data.val);
`else
        dataStore[w_req.wordIdx].write(getDataIdx(set, way), w_data.val);
`endif        
        debugLog.record($format("  WRITE Word: addr=0x%x, set=0x%x, way=%0d, word=%0d, data=0x%x", debugAddrFromTag(tag, set), set, way, w_req.wordIdx, w_data.val));

        if (! writeBackCache())
        begin
            // Send all writes to backing storage if in write-through mode.
            Vector#(nWordsPerLine, Bool) mask = replicate(False);
            mask[w_req.wordIdx] = True;
            Vector#(nWordsPerLine, t_CACHE_WORD) val = replicate(w_data.val);
            sourceData.write(cacheAddr(tag, set), mask, unpack(pack(val)));
        end
        reqInfo_writeData.free(w_req.dataIdx);
        doneQ.enq(set);
    endrule


    // ====================================================================
    //
    // Miss handlers.
    //
    // ====================================================================

    //
    // handleWordMissForRead --
    //     Line is present in the cache but incomplete.  Request the full line
    //     from backing storage and merge it into the line.
    //
    rule handleWordMissForRead (tpl_2(wordMissQ.first()) matches tagged HCOP_READ .rReq);
        match {.req_base, .req, .word_valid_mask, .maf_idx} = wordMissQ.first();
        wordMissQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;

        //
        // Miss.  Pick a victim.
        //
        readMissW.wset(rReq.readMeta);

        let addr = cacheAddr(tag, set);
        
        mafTable.write(maf_idx, tuple4(rReq.readMeta, rReq.wordIdx, word_valid_mask, req_base.way));
        sourceData.readReq(addr, maf_idx, rReq.globalReadMeta);
        debugLog.record($format("  READ WORD MISS (FILL): addr=0x%x, set=0x%x, way=%0d, maf_idx=%0d", 
                        debugAddr(addr), set, req_base.way, maf_idx));
    endrule


    //
    // handleMissForRead --
    //     Pick a victim and prepare to fill a way from backing storage.
    //
    (* conservative_implicit_conditions *)
    rule handleMissForRead (tpl_2(dataLookupQ.first()) matches tagged HCOP_READ .rReq &&& tpl_4(dataLookupQ.first()) == RL_SA_BRAM_CACHE_DATA_MISS);

        match {.req_base_in, .req, .word_valid_mask, .req_type} = dataLookupQ.first();
        match {.meta, .fill_way, .maf_idx} = lineMissQ.first();
        dataLookupQ.deq();
        lineMissQ.deq();

        t_CACHE_LINE flush_data <- getCacheLineDataResp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        readMissW.wset(rReq.readMeta);

        let req_base_out = req_base_in;
        req_base_out.way = fill_way;

        // Update LRU
        let meta_upd = meta;
        meta_upd.lru <- cacheLRUUpdate(set, fill_way, meta.lru);

        //
        // Update metadata here for the filled line since we have the details.
        //
        meta_upd.ways[fill_way] = tagged Valid metaData(tag, False, replicate(True), accessIncrementValue);
        metaStore.write(set, meta_upd);
        mafTable.write(maf_idx, tuple4(rReq.readMeta, rReq.wordIdx, replicate(False), fill_way));

        // Is victim dirty?
        Bool flushed_dirty = False;
        if (meta.ways[fill_way] matches tagged Valid .m)
        begin
            // Collect access statistics
            entryAccessesW.wset(m.accesses);
            invalEntryW.send();

            if (m.dirty)
            begin
                // Victim is dirty.  Flush data.
                flushed_dirty = True;
                dirtyEntryFlushW.send();
                debugLog.record($format("  READ MISS (DIRTY WB): addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(m.tag, set), set, fill_way, m.wordValid, flush_data));
                sourceData.write(cacheAddr(m.tag, set), m.wordValid, flush_data);
                // READ: Pass the request on to the fill stage.
                fillLineRequestQ.enq(tuple3(req_base_out, maf_idx, rReq.globalReadMeta));
            end
        end

        if (! flushed_dirty)
        begin
            let addr = cacheAddr(tag, set);
            sourceData.readReq(addr, maf_idx, rReq.globalReadMeta);
            debugLog.record($format("  READ MISS (FILL): addr=0x%x, set=0x%x, way=%0d, maf_idx=%0d", 
                            debugAddr(addr), set, fill_way, maf_idx));
        end
    endrule


    //
    // handleMissForWrite --
    //     Pick a victim and write back the dirty data, if needed.
    //
    (* mutually_exclusive = "flushDirtyLine, handleReadCacheHit, handleMissForRead, handleMissForWrite" *)
    (* conservative_implicit_conditions *)
    rule handleMissForWrite (tpl_2(dataLookupQ.first()) matches tagged HCOP_WRITE .wReq &&& tpl_4(dataLookupQ.first()) == RL_SA_BRAM_CACHE_DATA_MISS);

        match {.req_base_in, .req, .mask, .req_type} = dataLookupQ.first();
        match {.meta, .fill_way, .maf_idx} = lineMissQ.first();
        dataLookupQ.deq();
        lineMissQ.deq();

        t_CACHE_LINE flush_data <- getCacheLineDataResp();

        let tag = req_base_in.tag;
        let set = req_base_in.set;

        // no read meta available here
        writeMissW.wset(?);

        let req_base_out = req_base_in;
        req_base_out.way = fill_way;

        // Update LRU
        let meta_upd = meta;
        meta_upd.lru <- cacheLRUUpdate(set, fill_way, meta.lru);

        //
        // Update metadata here for the filled line since we have the details.
        //
        // The full line will not be filled from memory for a write.  Only
        // mark the word being written valid.
        t_CACHE_WORD_VALID_MASK word_valid_mask = replicate(False);
        word_valid_mask[wReq.wordIdx] = True;


        // Update tag and write metadata       
        meta_upd.ways[fill_way] = tagged Valid metaData(tag, writeBackCache(), word_valid_mask, accessIncrementValue);
        metaStore.write(set, meta_upd);

        // Is victim dirty?
        Bool flushed_dirty = False;
        if (meta.ways[fill_way] matches tagged Valid .m)
        begin
            // Collect access statistics
            entryAccessesW.wset(m.accesses);
            invalEntryW.send();

            if (m.dirty)
            begin
                // Victim is dirty.  Flush data.
                flushed_dirty = True;
                dirtyEntryFlushW.send();
                debugLog.record($format("  WRITE MISS (DIRTY WB): addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x", debugAddrFromTag(m.tag, set), set, fill_way, m.wordValid, flush_data));
                sourceData.write(cacheAddr(m.tag, set), m.wordValid, flush_data);
                // WRITE: Line is empty and ready to receive write data.
                writeDataQ.enq(tuple2(req_base_out, wReq));
            end
        end

        if (! flushed_dirty)
        begin
            // Writing does not require a fill.  Ready now.
            writeDataQ.enq(tuple2(req_base_out, wReq));
            debugLog.record($format("  Write to INVAL: addr=0x%x, set=0x%x, way=%0d", debugAddr(cacheAddr(tag, set)), set, fill_way));
        end
    endrule


    rule sendFillRequest (True);
        match {.req_base, .maf_idx, .global_read_meta} = fillLineRequestQ.first();
        fillLineRequestQ.deq();
        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;
        let addr = cacheAddr(tag, set);
        sourceData.readReq(addr, maf_idx, global_read_meta);
    endrule


    //
    // recvFillResp --
    //     receive fill response from next level memory
    //
    rule handleFillForRead (True);
        let rsp <- sourceData.readResp();
        match {.tag, .set} = cacheTagAndSet(rsp.addr);

        t_CACHE_REQ_BASE req_base;
        req_base.tag = tag;
        req_base.set = set;
        req_base.way = ?;
        
        mafTable.readReq(rsp.readMeta);
        mafLookupQ.enq(tuple5(req_base, rsp.val, rsp.globalReadMeta, rsp.readMeta, rsp.isCacheable));
    endrule

    //
    // handleFillForCacheableRead --
    //    Update the cache with requested data coming back from memory.
    //
    rule handleFillForCacheableRead (tpl_5(mafLookupQ.first()));
        //
        // Cache the new values.  Don't overwrite entries that are currently
        // valid, since they may be dirty.
        //
        // On return only claim that the newly filled words are valid.
        //
        let maf_data <- mafTable.readRsp();
        match {.client_meta, .word_idx, .cur_word_valid_mask, .cur_way} = maf_data;
        match {.req_base, .val, .global_read_meta, .maf_idx, .is_cacheable} = mafLookupQ.first();
        mafLookupQ.deq();
        mafTable.free(maf_idx);

        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));
        
        let tag = req_base.tag;
        let set = req_base.set;
        
        cacheLineDataWrite(set, cur_way, ret_valid_words, val);

        let r_req = RL_SA_BRAM_CACHE_READ_REQ { wordIdx: word_idx, 
                                                readMeta: client_meta, 
                                                globalReadMeta: global_read_meta };

        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         r_req,
                                         val,
                                         ret_valid_words,
                                         is_cacheable));

        debugLog.record($format("  Read FILL: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x",
                                debugAddrFromTag(tag, set), set, cur_way, ret_valid_words, val));
        doneQ.enq(req_base.set);
    endrule

    //
    // handleFillForUncacheableRead --
    //
    rule handleFillForUncacheableRead (!tpl_5(mafLookupQ.first()) && metaLookupQ.notFull());
        //
        // On return only claim that the newly filled words are valid.
        //
        let maf_data <- mafTable.readRsp();
        match {.client_meta, .word_idx, .cur_word_valid_mask, .cur_way} = maf_data;
        match {.req_base, .val, .global_read_meta, .maf_idx, .is_cacheable} = mafLookupQ.first();
        mafLookupQ.deq();
        mafTable.free(maf_idx);

        t_CACHE_WORD_VALID_MASK ret_valid_words = unpack(~pack(cur_word_valid_mask));

        let r_req = RL_SA_BRAM_CACHE_READ_REQ { wordIdx: word_idx, 
                                                readMeta: client_meta, 
                                                globalReadMeta: global_read_meta };
        let tag = req_base.tag;
        let set = req_base.set;
       
        readRespToClientQ_OOO.enq(tuple5(req_base,
                                         r_req,
                                         val,
                                         ret_valid_words,
                                         is_cacheable));

        debugLog.record($format("  Read FILL [NOT CACHEABLE]: addr=0x%x, set=0x%x, way=%0d, mask=0x%x, data=0x%x",
                                debugAddrFromTag(tag, set), set, cur_way, ret_valid_words, val));
        // Abnormal path.  Response is uncacheable.  The line has already
        // been marked valid in anticipation of the response, so the
        // metadata must now be fixed.
        let req_base_out = req_base;
        req_base_out.way = cur_way;
        metaStore.readReq(set);
        metaLookupReqW.wset(tuple3(req_base_out, tagged HCOP_READ r_req, RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE));
        fillLineUncacheableQ.enq(cur_word_valid_mask);
    endrule

    //
    // fixupUncacheableFillForRead --
    //     Fill response flaged the line uncacheable.  The way's metadata is
    //     speculatively set to valid when the fill is requested and must be
    //     marked invalid.
    //
    rule fixupUncacheableFillForRead (tpl_3(metaLookupQ.first()) == RL_SA_BRAM_CACHE_META_CLIENT_UNCACHEABLE);

        match {.req_base, .req, .lookup_type} = metaLookupQ.first();
        let old_word_valid_mask = fillLineUncacheableQ.first();
        fillLineUncacheableQ.deq();

        let meta <- metaStore.readRsp();
        metaLookupQ.deq();

        let tag = req_base.tag;
        let set = req_base.set;
        let way = req_base.way;

        // If no words were valid in the line before the fill then simply
        // mark the line invalid.  If words were valid then the line contained
        // partial write data.  In that case, restore the line to the state
        // before the fill request.
        let old_meta = validValue(meta.ways[way]);
        meta.ways[way] = (pack(old_word_valid_mask) == 0) ?
            tagged Invalid :
            tagged Valid metaData(old_meta.tag, old_meta.dirty, old_word_valid_mask, old_meta.accesses);

        metaStore.write(set, meta);

        debugLog.record($format("  Read FILL uncacheable: restored addr=0x%x, set=0x%x, way=%0d, mask=%b",
                        debugAddrFromTag(tag, set), set, way, old_word_valid_mask));

        doneQ.enq(set);
    endrule


    // ====================================================================
    //
    //   End of reference.
    //
    // ====================================================================

    // BE CAREFUL HERE!  Poor choice of order can cause deadlocks.
    (* descending_urgency = "doneWithRef, writeCacheData, fixupUncacheableFillForRead, handleFillForRead, handleFillForCacheableRead, handleFillForUncacheableRead, pickReqQueue, handleReadCacheHit, fwdInvalOrFlush, flushDirtyLine, sendFillRequest, handleWordMissForRead, handleMissForRead, handleMissForWrite, handleRead, handleWrite, handleInvalOrFlush" *)

    //
    // doneWithRef --
    //     All access paths terminate here.
    //
    rule doneWithRef (True);
        let set = doneQ.first();
        doneQ.deq();

        setFilter.remove(set);
        setFilterRemoveW.send();
    endrule


    // ====================================================================
    //
    //   Debug scan state
    //
    // ====================================================================

    List#(Tuple2#(String, Bool)) ds_data = List::nil;

    ds_data = List::cons(tuple2("SA BRAM Cache newReqQ NotEmpty", newReqQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache metaLookupQ NotEmpty", metaLookupQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache dataLookupQ NotEmpty", dataLookupQ.notEmpty), ds_data);

    ds_data = List::cons(tuple2("SA BRAM Cache writeDataQ NotEmpty", writeDataQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache writeDataQ NotFull", writeDataQ.notFull), ds_data);

    ds_data = List::cons(tuple2("SA BRAM Cache lineMissQ NotEmpty", lineMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache wordMissQ NotEmpty", wordMissQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache mafLookupQ NotEmpty", mafLookupQ.notEmpty), ds_data);

`ifndef RL_SA_BRAM_CACHE_PIPELINE_EN_Z
    ds_data = List::cons(tuple2("SA BRAM Cache metaProcessQ NotEmpty", metaProcessQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache dataStoreLookupInfoQ NotEmpty", dataStoreLookupInfoQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache dataStoreRspQ NotEmpty", dataStoreRspQ.notEmpty), ds_data);
`endif

    ds_data = List::cons(tuple2("SA BRAM Cache fillLineRequestQ NotEmpty", fillLineRequestQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache fillLineUncacheableQ NotEmpty", fillLineUncacheableQ.notEmpty), ds_data);
    ds_data = List::cons(tuple2("SA BRAM Cache doneQ NotEmpty", doneQ.notEmpty), ds_data);

    let debugScanData = ds_data;
    
    // ====================================================================
    //
    //   Incoming cache requests (methods)
    //
    // ====================================================================

    //
    // genRequest --
    //     This function is used by most of the request methods to generate
    //     the internal data structure for managing a request.  It also starts
    //     the first step:  reading metadata from BRAM.
    //
    function ActionValue#(t_CACHE_SET_IDX) genRequest(t_CACHE_REQ req,
                                                      t_CACHE_ADDR addr);
        actionvalue
            match {.tag, .set} = cacheTagAndSet(addr);

            t_CACHE_REQ_BASE req_base;
            req_base.tag = tag;
            req_base.set = set;
            req_base.way = ?;  // Way won't be known until the set meta data is read
            newReqQ.enq(tuple2(req_base, req));
            
            return set;
        endactionvalue
    endfunction

    //
    // readReq -- Read up to a full line.  Fetch from backing store if not in the cache.
    //
    method Action readReq(t_CACHE_ADDR addr,
                          Bit#(TLog#(nWordsPerLine)) wordIdx,
                          t_CACHE_READ_META readMeta,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta);

        RL_SA_BRAM_CACHE_READ_REQ#(nWordsPerLine, t_CACHE_READ_META) req;
        req.wordIdx = wordIdx;
        req.readMeta = readMeta;
        req.globalReadMeta = globalReadMeta;
        
        let set <- genRequest(tagged HCOP_READ req, addr);
        debugLog.record($format("  New request: READ addr=0x%x, set=0x%x, word=%0d", debugAddr(addr), set, wordIdx));
    endmethod

    method ActionValue#(t_CACHE_LOAD_RESP) readResp();
        match {.req_base, .r_req, .v, .valid_words, .is_cacheable} = readRespToClientQ_OOO.first();
        readRespToClientQ_OOO.deq();
        Vector#(nWordsPerLine, t_CACHE_WORD) value = unpack(pack(v));

        t_CACHE_LOAD_RESP rsp;
        for (Integer w = 0; w < valueOf(nWordsPerLine); w = w + 1)
            rsp.words[w] = valid_words[w] ? tagged Valid value[w] : tagged Invalid;
        rsp.addr = cacheAddr(req_base.tag, req_base.set);
        rsp.reqWordIdx = r_req.wordIdx;
        rsp.isCacheable = is_cacheable;
        rsp.readMeta = r_req.readMeta;
        rsp.globalReadMeta = r_req.globalReadMeta;

        return rsp;
    endmethod

    method t_CACHE_ADDR peekRespAddr();
        match {.req_base, .r_req, .v, .valid_words} = readRespToClientQ_OOO.first();
        return cacheAddr(req_base.tag, req_base.set);
    endmethod

    method Bool readRespReady();
        return readRespToClientQ_OOO.notEmpty();
    endmethod

    //
    // write -- Write a word to a line.
    //
    method Action write(t_CACHE_ADDR addr, t_CACHE_WORD val, t_CACHE_WORD_IDX wordIdx);
        t_CACHE_WRITE_INFO w_info;
        w_info.val = val;

        let h <- reqInfo_writeData.malloc();
        reqInfo_writeData.upd(h, w_info);

        RL_SA_BRAM_CACHE_WRITE_REQ#(nWordsPerLine) w_req;
        w_req.wordIdx = wordIdx;    
        w_req.dataIdx = h;

        let set <- genRequest(tagged HCOP_WRITE w_req, addr);

        debugLog.record($format("  New request: WRITE addr=0x%x, set=0x%x, data=0x%x, word=%0d, wData heap=%0d", debugAddr(addr), set, val, wordIdx, h));
    endmethod


    //
    // invalReq -- Invalidate (remove) a line from the cache
    //
    method Action invalReq(t_CACHE_ADDR addr, Bool sendAck);
        let set <- genRequest(tagged HCOP_INVAL sendAck, addr);
        debugLog.record($format("  New request: INVAL addr=0x%x, set=0x%x, needAck=%s", 
                        debugAddr(addr), set, sendAck? "True" : "False"));
    endmethod
    

    //
    // flushReq --
    //     Flush (write back) a line from the cache but keep the line cached.
    //
    method Action flushReq(t_CACHE_ADDR addr, Bool sendAck);
        let set <- genRequest(tagged HCOP_FLUSH_DIRTY sendAck, addr);
        debugLog.record($format("  New request: FLUSH addr=0x%x, set=0x%x, needAck=%s", 
                        debugAddr(addr), set, sendAck? "True" : "False"));
    endmethod

    //
    // invalOrFlushWait -- Block until an inval or flush request completes.
    //
    method Action invalOrFlushWait();
        debugLog.record($format("    INVAL/FLUSH complete"));
        sourceData.invalOrFlushWait();
    endmethod

    //
    // setCacheMode -- Configure cache behavior.
    //
    method Action setCacheMode(RL_SA_CACHE_MODE mode);
        if (cacheMode != mode)
        begin
            debugLog.record($format("Cache mode: %0d", mode));
        end
        cacheMode <= mode;    
    endmethod

    //
    // debugScanState -- Return cache state for DEBUG_SCAN.
    //
    method List#(Tuple2#(String, Bool)) debugScanState();
        return debugScanData;
    endmethod

    interface RL_CACHE_STATS stats;
        method readHit = readHitW.wget;
        method readMiss = readMissW.wget;
        method readRecentLineHit = False;
        method writeHit = writeHitW.wget;
        method writeMiss = writeMissW.wget;
        method newMRU = newMRUW;
        method invalEntry = invalEntryW;
        method dirtyEntryFlush = dirtyEntryFlushW;
        method forceInvalLine = forceInvalLineW;
        method entryAccesses = entryAccessesW.wget;
    endinterface

endmodule

