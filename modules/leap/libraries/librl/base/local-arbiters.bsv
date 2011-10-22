//
// Copyright (C) 2011 Intel Corporation
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
// LOCAL_ARBITER is an arbiter suitable for inclusion within a single rule.
// The standard Bluespec arbiter interface necessitates wires and, consequently,
// separation of rules for triggering requests and receiving grants.
//

interface LOCAL_ARBITER#(numeric type nCLIENTS);
    // If the value of "fixed" is True, the current grant is locked and not
    // updated again until "fixed" goes False.
    method ActionValue#(Maybe#(UInt#(TLog#(nCLIENTS)))) arbitrate(Vector#(nCLIENTS, Bool) req,
                                                                  Bool fixed);
endinterface

// Index of a single arbiter client
typedef UInt#(TLog#(nCLIENTS))  LOCAL_ARBITER_CLIENT_IDX#(numeric type nCLIENTS);

// Bit mask of all an arbiter's clients -- one bit per client.
typedef Vector#(nCLIENTS, Bool) LOCAL_ARBITER_CLIENT_MASK#(numeric type nCLIENTS);

// Abiter's internal, persistent, state
typedef struct
{
    LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS) priorityIdx;
}
LOCAL_ARBITER_OPAQUE#(numeric type nCLIENTS)
    deriving (Eq, Bits);


//
// localArbiterPickWinner --
//     Pick a winner given a set of requests and the current arbitration state.
//
//     This implementation uses vector functions instead of the loops found
//     in the Bluespec arbiter example.  Performance of the compiler in complex
//     cases is much improved using this style.
//
function Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)) localArbiterPickWinner(
    LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS) req,
    LOCAL_ARBITER_OPAQUE#(nCLIENTS) state);

    //
    // Clear the low priority portion of the request
    //
    function Bool maskOnlyHighPriority(Integer idx) = (fromInteger(idx) >= state.priorityIdx);
    let high_priority_mask = map(maskOnlyHighPriority, genVector());
    let high_priority_req = zipWith( \&& , req, high_priority_mask);

    //
    // Pick a winner
    //
    Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)) winner;
    if (findElem(True, high_priority_req) matches tagged Valid .idx)
        winner = tagged Valid idx;
    else
        winner = findElem(True, req);

    return winner;
endfunction


//
// localArbiterFunc --
//     Implementation of a local arbiter using a function.  This is the algorithm
//     used in mkLocalArbiter() below, but made available as a function so that
//     clients may manage their own storage.  A client instantiating a large
//     number of arbiters might use this in order to manage storage of
//     state efficiently.
//
function Tuple2#(Maybe#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS)),
                 LOCAL_ARBITER_OPAQUE#(nCLIENTS))
    localArbiterFunc(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS) req,
                     Bool fixed,
                     LOCAL_ARBITER_OPAQUE#(nCLIENTS) state);

    let n_clients = valueOf(nCLIENTS);

    let winner = localArbiterPickWinner(req, state);

    // If a grant was given, update the priority index so that client now has
    // lowest priority.
    let state_upd = state;
    if (! fixed &&& winner matches tagged Valid .idx)
    begin
        state_upd.priorityIdx = (idx == fromInteger(n_clients - 1)) ? 0 : idx + 1;
    end

    return tuple2(winner, state_upd);
endfunction


//
// mkLocalArbiter --
//   A fair round robin arbiter with changing priorities, inspired by the
//   Bluespec mkArbiter().
//
module mkLocalArbiter
    // Interface:
    (LOCAL_ARBITER#(nCLIENTS))
    provisos (Alias#(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS), t_CLIENT_MASK),
              Alias#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS), t_CLIENT_IDX));

    // Initially, priority is given to client 0
    Reg#(LOCAL_ARBITER_OPAQUE#(nCLIENTS)) state <- mkReg(unpack(0));

    method ActionValue#(Maybe#(t_CLIENT_IDX)) arbitrate(t_CLIENT_MASK req, Bool fixed);
        match {.winner, .state_upd} = localArbiterFunc(req, fixed, state);
        state <= state_upd;

        return winner;
    endmethod
endmodule


//
// mkLocalRandomArbiter --
//   Nearly identical to mkLocalArbiter() except the highest priority index
//   is chosen randomly.
//
module mkLocalRandomArbiter
    // Interface:
    (LOCAL_ARBITER#(nCLIENTS))
    provisos (Alias#(LOCAL_ARBITER_CLIENT_MASK#(nCLIENTS), t_CLIENT_MASK),
              Alias#(LOCAL_ARBITER_CLIENT_IDX#(nCLIENTS), t_CLIENT_IDX));

    // Initially, priority is given to client 0
    Reg#(LOCAL_ARBITER_OPAQUE#(nCLIENTS)) state <- mkReg(unpack(0));

    // LFSR for generating the next starting priority index.  Add a few bits
    // to add to the pattern.
    LFSR#(Bit#(TAdd#(3, TLog#(nCLIENTS)))) lfsr <- mkLFSR();

    method ActionValue#(Maybe#(t_CLIENT_IDX)) arbitrate(t_CLIENT_MASK req, Bool fixed);
        let winner = localArbiterPickWinner(req, state);

        if (! fixed)
        begin
            t_CLIENT_IDX next_idx = truncate(unpack(lfsr.value()));

            // Is the truncated LFSR value larger than nCLIENTS?  (Only happens
            // when the number of clients isn't a power of 2.
            if (next_idx > fromInteger(valueOf(TSub#(nCLIENTS, 1))))
            begin
                // This is unfair if the number of clients isn't a power of 2.
                next_idx = ~next_idx;
            end

            state.priorityIdx <= next_idx;
        end

        // Always run the LFSR to avoid timing dependence on the search result
        lfsr.next();

        return winner;
    endmethod
endmodule
