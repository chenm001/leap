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

import FIFO::*;
import DReg::*;

`include "awb/provides/librl_bsv_base.bsh"
`include "awb/provides/librl_bsv_cache.bsh"
`include "awb/provides/fpga_components.bsh"
`include "awb/provides/soft_connections.bsh"
`include "awb/provides/common_services.bsh"
    
    
// ===================================================================
//
// STATISTICS INTERFACE
//
// mkCentralCacheStats --
//     Statistics callbacks from central cache class.
//
// ===================================================================


module [CONNECTED_MODULE] mkCentralCacheStats#(RL_CACHE_STATS#(t_READ_META) cacheStats, Integer bankIdx)
    // interface:
    ();

    // Disambiguate central caches on multiple platforms    
    String platform <- getSynthesisBoundaryPlatform();

    String statsHeader = "LEAP_CENTRAL_CACHE_PLATFORM_" + platform + "_BANK_" + integerToString(bankIdx) + "_";

    STAT_ID statIDs[9];

    statIDs[0] = statName(statsHeader + "LOAD_HIT",
                          "Central Cache: Load hits");
    let statLoadHit = 0;

    statIDs[1] = statName(statsHeader + "LOAD_MISS",
                          "Central Cache: Load misses");
    let statLoadMiss = 1;

    statIDs[2] = statName(statsHeader + "STORE_HIT",
                          "Central Cache: Store hits");
    let statStoreHit  = 2;

    statIDs[3] = statName(statsHeader + "STORE_MISS",
                          "Central Cache: Store misses");
    let statStoreMiss = 3;

    statIDs[4] = statName(statsHeader + "INVAL_LINE",
                          "Central Cache: Lines invalidated due to capacity");
    let statInvalEntry = 4;

    statIDs[5] = statName(statsHeader + "DIRTY_LINE_FLUSH",
                          "Central Cache: Dirty lines flushed to memory");
    let statDirtyEntryFlush = 5;

    statIDs[6] = statName(statsHeader + "FORCE_INVAL_LINE",
                          "Central Cache: Lines forcibly invalidated (not due to capacity)");
    let statForceInvalLine = 6;

    statIDs[7] = statName(statsHeader + "LOAD_RECENT_LINE_HIT",
                          "Central Cache: Load recent line cache hits");
    let statLoadRecentLineHit = 7;

    statIDs[8] = statName(statsHeader + "LOAD_NEW_MRU",
                          "Central Cache: Reference changed MRU way for valid entry (hit)");
    let statNewMRU = 8;

    STAT_VECTOR#(9) stats <- mkStatCounter_Vector(statIDs);

    rule readHit (cacheStats.readHit() matches tagged Valid .meta);
        stats.incr(statLoadHit);
    endrule

    rule readMiss (cacheStats.readMiss() matches tagged Valid .meta);
        stats.incr(statLoadMiss);
    endrule

    rule writeHit (cacheStats.writeHit() matches tagged Valid .meta);
        stats.incr(statStoreHit);
    endrule

    rule writeMiss (cacheStats.writeMiss() matches tagged Valid .meta);
        stats.incr(statStoreMiss);
    endrule

    rule invalEntry (cacheStats.invalEntry());
        stats.incr(statInvalEntry);
    endrule

    rule dirtyEntryFlush (cacheStats.dirtyEntryFlush());
        stats.incr(statDirtyEntryFlush);
    endrule

    rule forceInvalLine (cacheStats.forceInvalLine());
        stats.incr(statForceInvalLine);
    endrule

    rule recentLineReadHit (cacheStats.readRecentLineHit());
        stats.incr(statLoadRecentLineHit);
    endrule

    rule newMRU (cacheStats.newMRU());
        stats.incr(statNewMRU);
    endrule

endmodule

