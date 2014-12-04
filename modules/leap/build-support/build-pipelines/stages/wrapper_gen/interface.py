import sys
import copy
import wrapper_gen_tool

class Interface():
  
    def __init__(self, type, name, members):
        self.type = type
        # A dictionary of names -> interface/methods
        self.name = name
        self.members = members
        self.attributes = {}

    def generateImportInterface(self, interfaceHandle, ifcEnv, namePrefix):
        #interfaces don't know their name. this must be propagated.
        for member in self.members:
            self.members[member].generateImportInterface(interfaceHandle, ifcEnv, namePrefix + '_' + str(self.members[member].name)) 
            self.attributes['namePrefix'] = namePrefix

    def generateImportInterfaceTop(self, interfaceHandle, ifcEnv):
        #interfaces don't know their name. this must be propagated.
        for member in self.members:
            self.members[member].generateImportInterface(interfaceHandle, ifcEnv, str(self.members[member].name)) 
            self.attributes['namePrefix'] = ''

    def generateImport(self, interfaceHandle, ifcEnv):
        #interfaces don't know their name. this must be propagated.
        interfaceHandle.write("//begin import subinterface " + self.name + "\n")
        for member in self.members:
            self.members[member].generateImport(interfaceHandle, ifcEnv) 

    def generateImportTop(self, interfaceHandle):
        #interfaces don't know their name. this must be propagated.
        interfaceHandle.write("//begin import\n")
        for member in self.members:
            self.members[member].generateImport(interfaceHandle, ifcEnv) 


    def generateHierarchy(self, interfaceHandle, ident, topModule, ifcEnv):
        #interfaces don't know their name. this must be propagated.
        # First I let my children write down their definitions. Then I
        # bind them.
        for member in self.members:
            self.members[member].generateHierarchy(interfaceHandle, ident + '\t', topModule, ifcEnv)

        # now I can create my binding.
        interfaceHandle.write(ident + "//begin import subinterface " + self.name + "\n")
        interfaceHandle.write(ident + self.type + " " + self.getDefinition() + " = interface " + self.type + ";\n")        
        for member in self.members:
            memberObj = self.members[member]
            if(isinstance(memberObj, wrapper_gen_tool.Method)):
                interfaceHandle.write(ident + "\tmethod " + memberObj.name + " = " + memberObj.getDefinition() + ";\n")
            else:
                interfaceHandle.write(ident + "\tinterface " + memberObj.name + " = " + memberObj.getDefinition() + ";\n")

        interfaceHandle.write(ident + "endinterface;\n")

    def getDefinition(self):
        return  "ifc_" + self.attributes['namePrefix'] + "_ifc"
      
