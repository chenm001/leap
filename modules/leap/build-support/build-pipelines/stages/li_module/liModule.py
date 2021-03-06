import sys
import copy


class LIModule():
  
    def __init__(self, type, name):
        self.type = type
        self.name = name
        self.channels = []    
        self.chains = []    
        self.services = []
        self.chainNames = {}
        self.channelNames = {}    
        self.serviceNames = {}

        self.attributes = {}
        
        # The module will also include references to the object code
        # necessary to build the module. This enables us to cache
        # compilation results in the multiple stage LIM flow

        self.objectCache = {}

        # The number of exported rules is a metric useful as a heuristic for
        # deciding where to emit synthesis boundaries instead of just Bluespec
        # modules.  A module that is, itself, a synthesis boundary exports
        # no rules.  A module that is not a synthesis boundary exports a
        # number of rules equal to the number of local rules for channels
        # plus the number of exported rules of its children.
        self.numExportedRules = 0

    def id(self):
        print "LIModule: " + self.name + ":"  + str(id(self)) + ':' + str(id(self.attributes))  
        for channel in self.channels:
            partnerID = str(id(channel.partnerModule))
            partnerName = 'unassigned'
            if(isinstance(channel.partnerModule, LIModule)):
                partnerName = channel.partnerModule.name
            print "\tchannel " + channel.name + ':' + str(id(channel)) + ' partner ' + partnerName + ':' + partnerID
        

    def __repr__(self):
        rep = "{ MODULE:" + self.name + ":" + self.type + ":\nChannels:" + ',\n'.join(map(str, self.channels))
        rep += ":\nChains:" + ',\n'.join(map(str, self.chains)) + "\nChainsNames:" + ',\n'.join(map(str, self.chainNames.keys()))
        rep += ":\nServices:" + ',\n'.join(map(str, self.services)) + "\nServiceNames:" + ',\n'.join(map(str, self.serviceNames.keys()))
        rep += "\nAttributes: " + str(self.attributes) + "}\n"
        return rep

    def unmatch(self):
        for channel in self.channels:
            channel.unmatch()

        for chain in self.chains:
            chain.unmatch()

        for service in self.services:
            service.unmatch()

    def copy(self):
        moduleCopy = LIModule(self.type, self.name)
        for channel in self.channels:
            moduleCopy.addChannel(channel.copy())
        for chain in self.chains:
            moduleCopy.addChain(chain.copy())
        for service in self.services: 
            moduleCopy.addService(service.copy())
        moduleCopy.numExportedRules = self.numExportedRules
        moduleCopy.attributes = copy.deepcopy(self.attributes)
        moduleCopy.objectCache = copy.deepcopy(self.objectCache)
        return moduleCopy  

    def addChannel(self, channel):
        channelCopy = channel.copy()
        channelCopy.module = self # You belong to me. 
        self.channels.append(channelCopy)
        self.channelNames[channelCopy.name] = channelCopy
        return channelCopy

    # it is nonsensical to have more than one instance of the same
    # chain, so we drop extraneous chain references. 
    def addChain(self, chain):
        if(not chain.name in self.chainNames):          
            chainCopy = chain.copy()
            chainCopy.module = self
            self.chains.append(chainCopy)
            self.chainNames[chainCopy.name] = chainCopy.name
            return chainCopy
        else:
            print "Warning, dropping spurious chain: " + chain.name + " in module " + self.name + "\n"
            return self.chainNames[chain.name]

    def deleteChain(self, chain):
        del self.chainNames[chain]
        self.chains = [memberChain for memberChain in self.chains if memberChain.name != chain]
    
    def addService(self, service):
        serviceCopy = service.copy()
        serviceCopy.module = self
        self.services.append(serviceCopy)
        self.serviceNames[serviceCopy.name] = serviceCopy
        return serviceCopy

    def setNumExportedRules(self, n):
        self.numExportedRules = n
 
    def putObjectCode(self, key, value):
        if (key in self.objectCache):
            if (isinstance(value,list)):
                self.objectCache[key] += value
            else:
                self.objectCache[key].append(value)
        else: 
            if (isinstance(value,list)):
                self.objectCache[key] = value
            else:
                self.objectCache[key] = [value]

    def getObjectCode(self, key):
        if(key in self.objectCache):
            return self.objectCache[key]
        else:
            return []

    def putAttribute(self, key, value):
        self.attributes[key] = value
        

    def getAttribute(self, key):
        if(key in self.attributes):
            return self.attributes[key]
        else:
            return None


    def trimOptionalChannels(self):
        self.channels = [channel for channel in self.channels if (channel.matched or not channel.optional)]

    def checkUnmatchedChannels(self):
        for channel in self.channels:
            if(not channel.matched and not channel.optional):
                return True
        return False

    def dumpUnmatchedChannels(self):
        for channel in self.channels:
            if(not channel.matched):
                print str(channel)



# These functions make it easier to decide which modules connect to
# to one another. They are mostly used in the LIM compiler.
def channelsByPartner(liModule, channelPartnerModule):
    for channel in liModule.channels:
        if(isinstance(channel.partnerModule, str)): 
            print "Channel " + channel.name + " is " + channel.partnerModule
        
    return [channel for channel in liModule.channels if (channel.partnerModule.name == channelPartnerModule)]

def ingressChainsByPartner(liModule, chainPartnerModule):
    for chain in liModule.chains:
        if(isinstance(chain.sourcePartnerModule, str)):
            print "Warning : " + str(chain) + "\n"
    return [chain for chain in liModule.chains if(chain.sourcePartnerModule.name == chainPartnerModule)]

def egressChainsByPartner(liModule, chainPartnerModule):
    for chain in liModule.chains:
        if(isinstance(chain.sinkPartnerModule, str)):
            print "Warning : " + str(chain) + "\n"
    return [chain for chain in liModule.chains if(chain.sinkPartnerModule.name == chainPartnerModule)]

def egressChannelsByPartner(liModule, channelPartnerModule):
    return [channel for channel in channelsByPartner(liModule, channelPartnerModule) if(channel.isSource())]

def ingressChannelsByPartner(liModule, channelPartnerModule):
    return [channel for channel in channelsByPartner(liModule, channelPartnerModule) if(not channel.isSource())]







