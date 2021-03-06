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
// Simple scratchpad interface that uses local memory refereces
// as the only backing storage.
//
// The scratchpad can access all of local memory and assumes that any sharing
// is managed by clients of the scratchpad.
// 

import FIFO::*;
import FIFOF::*;
import Vector::*;
import DefaultValue::*;

`include "awb/provides/soft_connections.bsh"
`include "awb/provides/soft_services.bsh"
`include "awb/provides/soft_services_lib.bsh"
`include "awb/provides/soft_services_deps.bsh"
`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/low_level_platform_interface.bsh"
`include "awb/provides/local_mem.bsh"
`include "awb/provides/physical_platform.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/librl_bsv_storage.bsh"
`include "awb/provides/scratchpad_memory_common.bsh"


//
// Scratchpad memory address and value.  awb parameter controls whether accesses
// are to local memory words or lines.
//
`ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
typedef LOCAL_MEM_ADDR SCRATCHPAD_MEM_ADDRESS;
typedef LOCAL_MEM_WORD SCRATCHPAD_MEM_VALUE;
typedef LOCAL_MEM_WORD_SZ SCRATCHPAD_MEM_VALUE_SZ;
typedef LOCAL_MEM_WORD_MASK SCRATCHPAD_MEM_MASK;
`else
typedef LOCAL_MEM_LINE_ADDR SCRATCHPAD_MEM_ADDRESS;
typedef LOCAL_MEM_LINE SCRATCHPAD_MEM_VALUE;
typedef LOCAL_MEM_LINE_SZ SCRATCHPAD_MEM_VALUE_SZ;
typedef LOCAL_MEM_LINE_MASK SCRATCHPAD_MEM_MASK;
`endif


typedef SCRATCHPAD_MEMORY_VIRTUAL_DEVICE#(SCRATCHPAD_MEM_ADDRESS,
                                          SCRATCHPAD_MEM_VALUE,
                                          SCRATCHPAD_MEM_MASK) SCRATCHPAD_MEMORY_VDEV;


//
// mkScratchpadMemory --
//     Build a scratchpad memory with the requested number of ports.
//
module [CONNECTED_MODULE] mkScratchpadMemory#(Integer memBankIdx)
    // interface:
    (SCRATCHPAD_MEMORY_VDEV)
    provisos (Bits#(SCRATCHPAD_MEM_ADDRESS, t_SCRATCHPAD_MEM_ADDRESS_SZ));

    let platformName <- getSynthesisBoundaryPlatform();
    let dbg_name = "memory_scratchpad_platform_" + platformName() + "_bank_" + integerToString(memBankIdx) + ".out";
    DEBUG_FILE debugLog <- (`SCRATCHPAD_MEMORY_DEBUG_ENABLE == 1)?
                           mkDebugFile(dbg_name):
                           mkDebugFileNull(dbg_name);

    //
    // Instantiate the shim to local memory.
    //
    LOCAL_MEM_CONFIG conf = defaultValue;
    conf.bankIdx = memBankIdx;
    LOCAL_MEM localMem <- mkLocalMem(conf);

    // Total memory allocated
    Reg#(SCRATCHPAD_MEM_ADDRESS) totalAlloc <- mkReg(0);

    // Port base-address within global memory.  Assigned dynamically as
    // allocation requests arrive.
    LUTRAM#(SCRATCHPAD_PORT_NUM, Maybe#(SCRATCHPAD_MEM_ADDRESS)) portSegmentBase <- mkLUTRAM(tagged Invalid);

    // Direct read responses to the correct port
    FIFOF#(Tuple3#(SCRATCHPAD_MEM_ADDRESS,
                   SCRATCHPAD_READ_UID,
                   RL_CACHE_GLOBAL_READ_META)) readQ <- mkSizedFIFOF(128);


    // ====================================================================
    //
    // Initialization.  All scratchpad memory is guaranteed to start
    // filled with zeros.
    //
    // ====================================================================

    FIFOF#(Tuple3#(SCRATCHPAD_PORT_NUM, SCRATCHPAD_MEM_ADDRESS, SCRATCHPAD_MEM_ADDRESS)) initQ <- mkFIFOF1();
    Reg#(Bool) initBusy <- mkReg(False);
    Reg#(SCRATCHPAD_PORT_NUM) initPort <- mkRegU();
    Reg#(SCRATCHPAD_MEM_ADDRESS) initAddrBase <- mkRegU();
    Reg#(SCRATCHPAD_MEM_ADDRESS) initAddr <- mkRegU();
    Reg#(SCRATCHPAD_MEM_ADDRESS) initCnt <- mkRegU();

    //
    // processInitReq --
    //     Initialization requests come from the init port interface below.
    //
    rule processInitReq (! initBusy);
        match {.port, .base_addr, .n_init} = initQ.first();
        initQ.deq();
        
`ifdef LOCAL_MEM_REQUIRES_ALLOC
        let m_alloc <- localMem.allocRegionRsp();
        if (! isValid(m_alloc))
        begin
            debugLog.record($format("INIT ALLOC port %0d: OUT OF MEMORY", port));
        end

        // Use the base address from the allocator
        if (m_alloc matches tagged Valid .alloc)
        begin
            debugLog.record($format("INIT ALLOC port %0d: 0x%x words, base 0x%x", port, n_init, base_addr));

  `ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
            base_addr = alloc.baseAddr;
  `else
            base_addr = localMemLineAddr(alloc.baseAddr);
  `endif
            if (! alloc.needsInitZero)
            begin
                n_init = 0;
            end
        end
`endif

        initBusy <= True;
        initPort <= port;
        initAddrBase <= base_addr;
        initAddr <= base_addr;
        initCnt <= n_init;
    endrule

    //
    // doInit --
    //     Main initialization loop.  Write 0 to a scratchpad.
    //
    rule doInit (initBusy);
`ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
        localMem.writeWord(initAddr, 0);
`else
        localMem.writeLine(localMemLineAddrToAddr(initAddr), 0);
`endif

        // Done?
        if (initCnt == 0)
        begin
            // Flag the segment ready by setting its translation to a local
            // memory region.
            portSegmentBase.upd(initPort, tagged Valid initAddrBase);
            initBusy <= False;
            debugLog.record($format("INIT port %0d: done", initPort));
        end
        
        initAddr <= initAddr + 1;
        initCnt <= initCnt - 1;
    endrule


    // ====================================================================
    //
    // Scratchpad port methods.
    //
    // ====================================================================

    function Bool initDone = ! (initBusy || initQ.notEmpty());

    method Action readReq(SCRATCHPAD_MEM_ADDRESS addr,
                          SCRATCHPAD_MEM_MASK byteMask,
                          SCRATCHPAD_READ_UID readUID,
                          RL_CACHE_GLOBAL_READ_META globalReadMeta) if (initDone());
        if (portSegmentBase.sub(readUID.portNum) matches tagged Valid .segment_base)
        begin
            let p_addr = addr + segment_base;
            debugLog.record($format("readReq port %0d: addr 0x%x, p_addr 0x%x", readUID.portNum, addr, p_addr));

            readQ.enq(tuple3(addr, readUID, globalReadMeta));

`ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
            localMem.readWordReq(p_addr);
`else
            localMem.readLineReq(localMemLineAddrToAddr(p_addr));
`endif
        end
        else
        begin
            debugLog.record($format("ERROR: read before init %0d", readUID.portNum));
        end
    endmethod

    method ActionValue#(SCRATCHPAD_READ_RESP#(SCRATCHPAD_MEM_ADDRESS,
                                              SCRATCHPAD_MEM_VALUE)) readRsp();
`ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
        let val <- localMem.readWordRsp();
`else
        let val <- localMem.readLineRsp();
`endif
        match {.addr, .read_uid, .global_read_meta} = readQ.first();
        readQ.deq();

        debugLog.record($format("readRsp port %0d: 0x%x", read_uid.portNum, val));

        SCRATCHPAD_READ_RESP#(SCRATCHPAD_MEM_ADDRESS, SCRATCHPAD_MEM_VALUE) r;
        r.val = val;
        r.addr = addr;
        r.readUID = read_uid;
        r.isCacheable = True;
        r.globalReadMeta = global_read_meta;

        return r;
    endmethod

    //
    // write --
    //     write method is predicated by readQ.notFull() to ensure
    //     synchronization of read and write requests.
    //
    method Action write(SCRATCHPAD_MEM_ADDRESS addr,
                        SCRATCHPAD_MEM_VALUE val,
                        SCRATCHPAD_PORT_NUM portNum) if (initDone() &&& readQ.notFull());
        if (portSegmentBase.sub(portNum) matches tagged Valid .segment_base)
        begin
            let p_addr = addr + segment_base;
            debugLog.record($format("write port %0d: addr 0x%x, p_addr 0x%x, 0x%x", portNum, addr, p_addr, val));

`ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
            localMem.writeWord(p_addr, val);
`else
            localMem.writeLine(localMemLineAddrToAddr(p_addr), val);
`endif
        end
    endmethod


    //
    // writeMasked --
    //     Same as write() but only write the bytes flagged in byteWriteMask.
    //
    method Action writeMasked(SCRATCHPAD_MEM_ADDRESS addr,
                              SCRATCHPAD_MEM_VALUE val,
                              SCRATCHPAD_MEM_MASK byteWriteMask,
                              SCRATCHPAD_PORT_NUM portNum) if (initDone() &&& readQ.notFull());
        if (portSegmentBase.sub(portNum) matches tagged Valid .segment_base)
        begin
            let p_addr = addr + segment_base;
            debugLog.record($format("write masked port %0d: addr 0x%x, p_addr 0x%x, val 0x%x, mask %b", portNum, addr, p_addr, val, pack(byteWriteMask)));

`ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
            localMem.writeWordMasked(p_addr, val, byteWriteMask);
`else
            localMem.writeLineMasked(localMemLineAddrToAddr(p_addr),
                                     val, byteWriteMask);
`endif
        end
    endmethod


    //
    // Initialization
    //
    method ActionValue#(Bool) init(SCRATCHPAD_MEM_ADDRESS allocLastWordIdx,
                                   SCRATCHPAD_PORT_NUM portNum,
                                   Bool useCentralCache,
                                   Maybe#(GLOBAL_STRING_UID) initFilePath,
                                   Bool initCacheOnly);
        SCRATCHPAD_MEM_ADDRESS last_word = totalAlloc + allocLastWordIdx;

        // Arithmetic for debug (includes overflow bit)
        Bit#(TAdd#(1, t_SCRATCHPAD_MEM_ADDRESS_SZ)) dbg_alloc_last_word_idx = zeroExtend(allocLastWordIdx) + 1;
        Bit#(TAdd#(1, t_SCRATCHPAD_MEM_ADDRESS_SZ)) dbg_last_word = zeroExtend(last_word) + 1;
        debugLog.record($format("INIT port %0d: 0x%x words, base 0x%x, next 0x%x", portNum, dbg_alloc_last_word_idx, totalAlloc, dbg_last_word));

        Bool ok = True;
        if (last_word > totalAlloc)
        begin
            initQ.enq(tuple3(portNum, totalAlloc, allocLastWordIdx));

`ifdef LOCAL_MEM_REQUIRES_ALLOC
            //
            // Local memory requires explicit allocation.
            //
  `ifdef SCRATCHPAD_MEMORY_USE_LINES_Z
            localMem.allocRegionReq(allocLastWordIdx);
  `else
            localMem.allocRegionReq(localMemLineAddrToAddr(allocLastWordIdx));
  `endif
`endif
        end
        else
        begin
            debugLog.record($format("INIT port %0d: OUT OF MEMORY", portNum));
            ok = False;
        end

        totalAlloc <= last_word + 1;
        return ok;
    endmethod
endmodule
