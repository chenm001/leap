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

#include <stdio.h>
#include <unistd.h>
#include <strings.h>
#include <assert.h>
#include <stdlib.h>
#include <sys/select.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <signal.h>
#include <string.h>
#include <time.h>
#include <iostream>
#include "awb/provides/channelio.h"
#include "awb/provides/li_base_types.h"
#include "awb/provides/multifpga_switch.h"

using namespace std;

// ============================================
//                 LI Channel Base Classes                
// ============================================



// ============================================
//                 Channel I/O                 
// ============================================

// constructor -- maybe it should be virtual?
CHANNELIO_BASE_CLASS::CHANNELIO_BASE_CLASS(
    PLATFORMS_MODULE parent,
    PHYSICAL_DEVICES devices) :
    PLATFORMS_MODULE_CLASS(parent),
    incomingHandlers()
{
    physicalDevices = devices;
}

// destructor 
CHANNELIO_BASE_CLASS::~CHANNELIO_BASE_CLASS()
{

}

void CHANNELIO_BASE_CLASS::Uninit()
{
}
 
bool CHANNELIO_BASE_CLASS::UninitComplete()
{
    // Wait for our threads to get cancelled.
    for(std::vector<pthread_t*>::iterator channelsIter = incomingHandlers.begin(); 
            channelsIter != incomingHandlers.end(); channelsIter++)   
    {   
        pthread_join(*(*channelsIter), NULL);
    }

    return true;
}



// Specialized marshalling logic for handling the UMF_MESSAGE type.

template<> void MARSHALLED_LI_CHANNEL_IN_CLASS<UMF_MESSAGE>::pushUMF(UMF_MESSAGE &incoming) 
{
    // Although the input queue has type UMF message, 
    // We can't directly do this write.  We need to translate the base message type
    // into the RRR style umf message.
    // first decode header
    UMF_MESSAGE element = new UMF_MESSAGE_CLASS();
    // This is so dirty, I can't believe that I'm writing it. 
    *((UMF_CHUNK*) element) = incoming->ExtractChunk();

    channelPartner->push(element); // Stuff this in our input Q.

    // Handle flow control.  
    // this code is common to all channels and should be moved up in the class
    // hierarchy.
    // Our flowcontrol variable appears not to need to be atomic.
    // UINT64 tempCredits = flowcontrolCredits + ((1+appends) * 3);
    acquireCredits(3);

    if(DEBUG_CHANNELIO) 
    {
        debugLog << "Channel is  " << this << endl;        
    }

    freeCredits(incoming->GetServiceID());

    if(DEBUG_CHANNELIO) 
    {
        debugLog << "****Channel " << this->name << " incoming message is complete" << endl; 
    }

    delete incoming; // We've translated the message, so get rid of it...

}

// This push is the push inherited from LI_CHANNEL_SEND.  It is user-facing
template<> void MARSHALLED_LI_CHANNEL_OUT_CLASS<UMF_MESSAGE>::push(UMF_MESSAGE &element) 
{
    //  TODO: Currently pushes are non-atomic, which means that they can get interleaved. 
    //  The mutex fixes this, but a better solution would be to construct a linked list and
    //  use the lock-free queue. 
    std::unique_lock<std::mutex> lk(pushMutex); 

    // Check for space in flow control 
    // RRR allows small size/packed bytes.  We account for that here...
    // TODO: These values are probably constant. We should store as a static class variable.
    UINT32 extraChunk = ((element->GetLength()%sizeof(UMF_CHUNK)) != 0) ? 1 : 0; 
    UINT32 messageLength = (element->GetLength()/sizeof(UMF_CHUNK) + extraChunk + 1) * 3;  // Each chunk takes a header plus one bit for encoding?

    acquireCredits(messageLength);

    // Send header first
    {
        UMF_CHUNK baseHeader = element->EncodeHeaderWithPhyChannelPvt(packetNumber & 0x3f);          
        element->SetPhyPvt( packetNumber & 0x3f);

        if(DEBUG_CHANNELIO) 
        {
            debugLog << this->name <<" packet number 0x" << hex << packetNumber << " truncated to seq" << (packetNumber & 0x3f) <<endl;
            chunkNumber ++;
            packetNumber++;

            debugLog << endl << "****Channel "<< this->name << " Sends message " << endl;               
            debugLog << endl << "Base Message length "<< dec << (UINT32) (element->GetLength()) << endl;  
            debugLog << "Message Credits "<< dec << messageLength << endl;
            debugLog << "Channel ID (LIM) "<< dec << this->channelID << endl;
            debugLog << "Original RRR message "<< dec << this->channelID << endl;
            element->Print(debugLog);
        }

        UMF_MESSAGE outMesg = factory->createUMFMessage();
        outMesg->SetLength(2 * sizeof(UMF_CHUNK)); 
        outMesg->SetServiceID(this->channelID);
        outMesg->AppendChunk(baseHeader);
        outMesg->AppendChunk(0);

        if(DEBUG_CHANNELIO) 
        {
            debugLog << "New header "<< endl;
            outMesg->Print(debugLog);
        }

        outputQ->push(outMesg);
    }

    element->StartExtract();
    while (element->CanExtract())
    {
        if(DEBUG_CHANNELIO) 
        {
            debugLog << "packet bytes remaining: " << element->ExtractBytesLeft() << endl;
        }

        UMF_CHUNK chunk = element->ExtractChunk();
        UMF_MESSAGE outMesg = factory->createUMFMessage();
        chunkNumber ++;

        if(DEBUG_CHANNELIO) 
        {
            debugLog << endl <<"Sending payload chunk " << this-> name;
            debugLog << " Factory ptr: " << factory << " Mesg ptr: " << outMesg << endl;
            outMesg->Print(debugLog);
	}

        outMesg->SetLength(2 * sizeof(UMF_CHUNK));

        if(DEBUG_CHANNELIO) 
        {
            debugLog << "Reading Channel "<< this << endl;
            debugLog << "Name "<< this->name << endl;
            debugLog << "ID " << this->channelID << endl;
	}

        outMesg->SetServiceID(this->channelID);
        outMesg->AppendChunk(chunk);
        outMesg->AppendChunk(1);  

        if(DEBUG_CHANNELIO) 
        {
            debugLog << "Pushing message to output Q" << endl;
            outMesg->Print(debugLog);
	}

        outputQ->push(outMesg);
    } 

    if(DEBUG_CHANNELIO) 
    {

        debugLog << this->name << " chunk number 0x" << hex << chunkNumber <<endl;
        debugLog << endl << "****Channel "<< this->name << " Send message complete" << endl;               
    }


    UMF_MESSAGE elementCopy = element;
    delete elementCopy; // Should we delete here?
}


// Specialized marshalling logic for handling the UINT64 type.

template<> void MARSHALLED_LI_CHANNEL_IN_CLASS<UINT128>::pushUMF(UMF_MESSAGE &incoming) 
{
    // Although the input queue has type UMF message, 
    UINT128 element;
    UINT8 appends = 0, rotation;
    UMF_CHUNK rotatedChunk, chunk1, chunk2;

    element = incoming->ExtractChunk();

    channelPartner->push(element);
    
    // Handle flow control.  
    // this code is common to all channels and should be moved up in the class
    // hierarchy.
    // Our flowcontrol variable appears not to need to be atomic.
    acquireCredits(2);

    if(DEBUG_CHANNELIO) 
    {
        debugLog << "(UINT128) Channel is  " << this << endl;
        
    }

    freeCredits(incoming->GetServiceID());

    if(DEBUG_CHANNELIO) 
    {
        debugLog << "****Channel " << this->name << " incoming message is complete" << endl; 
    }

    delete incoming; // We've translated the message, so get rid of it...
    
}


// This push is the push inherited from LI_CHANNEL_SEND.  It is user-facing
template<> void MARSHALLED_LI_CHANNEL_OUT_CLASS<UINT128>::push(UINT128 &element) 
{
    // Check for space in flow control 
    // RRR allows small size/packed bytes.  We account for that here...
   
    acquireCredits(2);

    {
        UMF_MESSAGE outMesg = factory->createUMFMessage();
        outMesg->SetLength(sizeof(UINT128)); 
        outMesg->SetServiceID(this->channelID);
	outMesg->AppendChunk(element);
        outputQ->push(outMesg);
    }

}

