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
// FIFOs with data stored in a large memory (e.g. BRAM).
//

import FIFO::*;
import FIFOF::*;
import FIFOLevel::*;
import SpecialFIFOs::*;
import Connectable::*;
import GetPut::*;
import DefaultValue::*;

`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_base.bsh"


// ========================================================================
//
//   FIFOs stored in either BRAM or LUTRAM, picked heuristically depending
//   on size.
//
// ========================================================================

//
// Parameters for configuring the heuristic that picks either BRAM or LUTRAM
// for a FIFO.
//
typedef struct
{
    // FIFO must be at least this deep before it is stored in BRAM.
    Integer minEntriesForBRAM;
    // Total FIFO size must be at least this large before picking BRAM.
    Integer minTotalBitsForBRAM;
}
AUTO_SIZED_FIFO_CONFIG;

instance DefaultValue#(AUTO_SIZED_FIFO_CONFIG);
    defaultValue = AUTO_SIZED_FIFO_CONFIG {
        minEntriesForBRAM: `FIFO_MEM_MIN_ENTRIES_FOR_BRAM,
        minTotalBitsForBRAM: `FIFO_MEM_MIN_TOTAL_BITS_FOR_BRAM
    };
endinstance


//
// mkSizedAutoMemFIFOF --
//   Build sized FIFOF using either mkSizedBRAMFIFOF or mkSizedFIFOF.
//   The choice depends on the requested size and the heuristic configuration
//   set in "heur".  Note that "heur" has an optional defaultValue.
//
module mkSizedAutoMemFIFOF#(Integer nEntries, AUTO_SIZED_FIFO_CONFIG heur)
    // Interface:
    (FIFOF#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    FIFOF#(t_DATA) _fifof;

    if ((nEntries >= heur.minEntriesForBRAM) &&
        (nEntries * valueOf(t_DATA_SZ) >= heur.minTotalBitsForBRAM))
    begin
        _fifof <- mkSizedBRAMFIFOF(nEntries);
    end
    else
    begin
        _fifof <- mkSizedFIFOF(nEntries);
    end

    return _fifof;
endmodule


//
// mkSizedAutoMemFIFO --
//   Same as mkSizedAutoMemFIFOF but a FIFO instead of a FIFOF.
//
module mkSizedAutoMemFIFO#(Integer nEntries, AUTO_SIZED_FIFO_CONFIG heur)
    // Interface:
    (FIFO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    FIFOF#(t_DATA) _fifof <- mkSizedAutoMemFIFOF(nEntries, heur);
    return fifofToFifo(_fifof);
endmodule


// ========================================================================
//
//   FIFOs stored in BRAM.
//
// ========================================================================

//
// mkSizedBRAMFIFO --
//     BRAM version of a memory FIFO.
//
module mkSizedBRAMFIFO#(Integer nEntries)
    // Interface:
    (FIFO#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
     
    FIFOF#(t_DATA) _fifof <- mkSizedBRAMFIFOF(nEntries);
    return fifofToFifo(_fifof);
endmodule


//
// mkSizedBRAMFIFOF --
//     BRAM version of a memory FIFOF.
//
//     We wrote these before the Bluespec library's equivalent function was
//     available.  The brute-force conversion of an integer parameter to
//     a type was adapted from the Bluespec code, replacing our old version
//     that took a type.  Too bad Integer can't be converted to a type.
//
module mkSizedBRAMFIFOF#(Integer depth)
    // Interface:
    (FIFOF#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));
     
    let _f = ?;

    if      (depth <= 2)          begin MEMORY_IFC#(Bit#(1), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4)          begin MEMORY_IFC#(Bit#(2), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 8)          begin MEMORY_IFC#(Bit#(3), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 8) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 16)         begin MEMORY_IFC#(Bit#(4), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 16) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 32)         begin MEMORY_IFC#(Bit#(5), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 32) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 64)         begin MEMORY_IFC#(Bit#(6), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 64) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 128)        begin MEMORY_IFC#(Bit#(7), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 128) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 256)        begin MEMORY_IFC#(Bit#(8), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 256) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 512)        begin MEMORY_IFC#(Bit#(9), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 512) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 1024)       begin MEMORY_IFC#(Bit#(10), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 1024) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 2048)       begin MEMORY_IFC#(Bit#(11), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2048) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4096)       begin MEMORY_IFC#(Bit#(12), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4096) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 8192)       begin MEMORY_IFC#(Bit#(13), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 8192) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 16384)      begin MEMORY_IFC#(Bit#(14), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 16384) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 32768)      begin MEMORY_IFC#(Bit#(15), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 32768) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 65536)      begin MEMORY_IFC#(Bit#(16), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 65536) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 131072)     begin MEMORY_IFC#(Bit#(17), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 131072) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 262144)     begin MEMORY_IFC#(Bit#(18), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 262144) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 524288)     begin MEMORY_IFC#(Bit#(19), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 524288) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 1048576)    begin MEMORY_IFC#(Bit#(20), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 1048576) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 2097152)    begin MEMORY_IFC#(Bit#(21), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2097152) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4194304)    begin MEMORY_IFC#(Bit#(22), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4194304) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 8388608)    begin MEMORY_IFC#(Bit#(23), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 8388608) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 16777216)   begin MEMORY_IFC#(Bit#(24), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 16777216) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 33554432)   begin MEMORY_IFC#(Bit#(25), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 33554432) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 67108864)   begin MEMORY_IFC#(Bit#(26), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 67108864) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 134217728)  begin MEMORY_IFC#(Bit#(27), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 134217728) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 268435456)  begin MEMORY_IFC#(Bit#(28), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 268435456) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 536870912)  begin MEMORY_IFC#(Bit#(29), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 536870912) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 1073741824) begin MEMORY_IFC#(Bit#(30), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 1073741824) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 2147483648) begin MEMORY_IFC#(Bit#(31), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 2147483648) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end
    else if (depth <= 4294967296) begin MEMORY_IFC#(Bit#(32), t_DATA) mem <- mkBRAMUnguarded(); FIFOCountIfc#(t_DATA, 4294967296) fifo <- mkMemoryFIFOF(mem); _f = fifoCountToFifof(fifo); end

    return _f;
endmodule


//
// mkSizedSlowBRAMFIFOF --
//   The slow variant of sized BRAM FIFOs is identical except that a buffer
//   is added on the receiver side to relax timing from BRAM read to consumer.
//
module mkSizedSlowBRAMFIFOF#(Integer depth)
    // Interface:
    (FIFOF#(t_DATA))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    FIFOF#(t_DATA) _f <- mkSizedBRAMFIFOF(depth);
    FIFOF#(t_DATA) _buf <- mkFIFOF();

    mkConnection(toGet(_f), toPut(_buf));

    method enq = _f.enq;
    method first = _buf.first;
    method deq = _buf.deq;
    method notEmpty = _buf.notEmpty;
    method notFull = _f.notFull;

    method Action clear();
        _f.clear();
        _buf.clear();
    endmethod
endmodule


//
// mkSizedBRAMFIFOCount --
//     BRAM version of a memory FIFOCountF.
//
module mkSizedBRAMFIFOCount
    // Interface:
    (FIFOCountIfc#(t_DATA,n_ENTRIES))
    provisos (Bits#(t_DATA, t_DATA_SZ));

    MEMORY_IFC#(Bit#(TLog#(n_ENTRIES)), t_DATA) mem <- mkBRAMUnguarded();
    FIFOCountIfc#(t_DATA,n_ENTRIES) _fifo <- mkMemoryFIFOF(mem);
    return _fifo;
endmodule


//
// mkMemoryFIFOF --
//     Implement a FIFOF in the provided memory (e.g. BRAM).  
//
//     To guarantee timing, the memory must have two characteristics:
//         1.  Reads and writes are unguarded.
//         2.  Read data is available one cycle following a read request.
//
//
module mkMemoryFIFOF#(MEMORY_IFC#(Bit#(TLog#(n_ENTRIES)), t_DATA) mem)
    // Interface:
    (FIFOCountIfc#(t_DATA, n_ENTRIES))
    provisos (Bits#(t_DATA, t_DATA_SZ));
    
    Reg#(FUNC_FIFO_IDX#(n_ENTRIES)) state <- mkReg(funcFIFO_IDX_Init());


    //
    // updateState --
    //     Combine deq and enq requests into an update of the FIFO state.
    //     Also fetch the value that could be returned by first() in the
    //     next cycle.
    RWire#(t_DATA) enqData <- mkRWire();
    PulseWire deqReq <- mkPulseWire();
    PulseWire clearReq <- mkPulseWire();
    
    Reg#(Maybe#(t_DATA)) bypassFirstVal <- mkReg(tagged Invalid);

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule updateState;
        FUNC_FIFO_IDX#(n_ENTRIES) new_state = state;
        Bool made_mem_req = False;
        
        // DEQ requested?
        if (deqReq)
        begin
            new_state = funcFIFO_IDX_UGdeq(new_state);
        end

        // After DEQ does the FIFO have more entries?  If yes, request the
        // value of the next entry.  It will be consumed by firstFromMem.
        if (funcFIFO_IDX_notEmpty(new_state))
        begin
            mem.readReq(funcFIFO_IDX_UGfirst(new_state));
            made_mem_req = True;
        end

        Maybe#(t_DATA) bypass_first = tagged Invalid;

        if (enqData.wget() matches tagged Valid .data)
        begin
            match {.s, .idx} = funcFIFO_IDX_UGenq(new_state);
            new_state = s;
            mem.write(idx, data);

            if (! made_mem_req)
            begin
                // No memory request is being issued this cycle either because
                // the FIFO was empty or is now empty following a deq.
                // Pass the new data directly to next cycle's first().
                bypass_first = tagged Valid data;
            end
        end

        //Clear takes precendent
        if(clearReq)
        begin
            new_state = funcFIFO_IDX_Init();
            bypass_first = tagged Invalid;
        end

        bypassFirstVal <= bypass_first;
        state <= new_state;
    endrule


    //
    // The value for the first() method must be requested the previous cycle
    // since memory reads are two phases.  The value comes from the updateState
    // rule either as a bypass or as a memory read response.
    //
    RWire#(t_DATA) firstVal <- mkRWire();

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule firstFromBypass (bypassFirstVal matches tagged Valid .val);
        firstVal.wset(val);
    endrule

    (* fire_when_enabled *)
    (* no_implicit_conditions *)
    rule firstFromMemRsp (! isValid(bypassFirstVal) &&
                          funcFIFO_IDX_notEmpty(state));
        let v <- mem.readRsp();
        firstVal.wset(v);
    endrule


    // ====================================================================
    //
    // Methods
    //
    // ====================================================================

    method Action enq(t_DATA data) if (funcFIFO_IDX_notFull(state));
        enqData.wset(data);
    endmethod

    method t_DATA first() if (firstVal.wget() matches tagged Valid .val);
        return val;
    endmethod

    method Action deq() if (firstVal.wget() matches tagged Valid .val);
        deqReq.send();
    endmethod

    method Action clear();
        clearReq.send();
    endmethod

    method Bool notEmpty();
        return funcFIFO_IDX_notEmpty(state);
    endmethod

    method Bool notFull();
        return funcFIFO_IDX_notFull(state);
    endmethod

    method UInt#(TLog#(TAdd#(n_ENTRIES,1))) count();
        return unpack(funcFIFO_IDX_numBusySlots(state));
    endmethod

endmodule


module mkSizedLUTRAMFIFOFUG#(NumTypeParam#(t_DEPTH) dummy) 
  //
  //interface:
              (FIFOF#(data_T))
  provisos
          (Bits#(data_T, data_SZ));

  LUTRAM#(Bit#(TLog#(t_DEPTH)), data_T) rs <- mkLUTRAMU();
  
  COUNTER#(TLog#(t_DEPTH)) head <- mkLCounter(0);
  COUNTER#(TLog#(t_DEPTH)) tail <- mkLCounter(0);

  Bool full  = head.value() == (tail.value() + 1);
  Bool empty = head.value() == tail.value();
    
  method Action enq(data_T d);
  
    rs.upd(tail.value(), d);
    tail.up();
   
  endmethod  
  
  method data_T first();
    
    return rs.sub(head.value());
  
  endmethod   
  
  method Action deq();
  
    head.up();
    
  endmethod

  method Action clear();
  
    tail.setC(0);
    head.setC(0);
    
  endmethod

  method Bool notEmpty();
    return !empty;
  endmethod
  
  method Bool notFull();
    return !full;
  endmethod

endmodule


module mkSizedLUTRAMFIFOF#(NumTypeParam#(t_DEPTH) dummy) 
    //
    //interface:
              (FIFOF#(data_T))
    provisos
          (Bits#(data_T, data_SZ));

    let q <- mkSizedLUTRAMFIFOFUG(dummy);
    
    method Action enq(data_T d) if (q.notFull);

        q.enq(d);   

    endmethod  
  
    method data_T first() if (q.notEmpty);

        return q.first();     

    endmethod   
  
    method Action deq() if (q.notEmpty);
  
        q.deq();
    
    endmethod

    method clear = q.clear;
  
    method notEmpty = q.notEmpty;
  
    method notFull = q.notFull;

endmodule


module mkSizedLUTRAMFIFO#(NumTypeParam#(t_DETPH) dummy)
    // Interface:
    (FIFO#(data_T))
    provisos (Bits#(data_T, data_SZ));

    let _q <- mkSizedLUTRAMFIFOF(dummy);
    return fifofToFifo(_q);
endmodule
