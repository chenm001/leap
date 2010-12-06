import os
import sys
import re
import SCons.Script
from model import  *
from config import *

def get_wrapper(module):
  return  module.name + '_Wrapper.bsv'


def get_child_v(module):
  return module.buildPath + '/.bsc/' + module.name + '_Wrapper.bi'


#this might be better implemented as a 'Node' in scons, but 
#I want to get something working before exploring that path
# This is going to recursively build all the bsvs
class BSV():

  def __init__(self, moduleList):
   
    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']

    moduleList.env['DEFS']['CWD_REL'] = moduleList.env['DEFS']['ROOT_DIR_HW_MODEL']

    #should we be building in events? 
    if (getEvents(moduleList) == 0):
       bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=False '
    else:
       bsc_events_flag = ' -D HASIM_EVENTS_ENABLED=True '

    self.BSC_FLAGS = BSC_FLAGS  + bsc_events_flag 

   
    topo = moduleList.topologicalOrderSynth()
    topo.reverse()
    # we probably want reverse topological ordering...
    for module in topo:
      # this should really be a crawl of the bluespec tree
      # probably in that case we can avoid a lot of synthesis time     
      # everyone should depend on the verilog wrappers?
      wrapper_v = self.build_synth_boundary(moduleList, module)
    

    moduleList.env.BuildDir(TMP_BSC_DIR, '.', duplicate=0)
    moduleList.env['ENV']['BUILD_DIR'] = moduleList.env['DEFS']['BUILD_DIR']  # need to set the builddir for synplify


  def build_synth_boundary(self,moduleList,module):
    env = moduleList.env
    MODULE_PATH =  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' 
    WRAPPER_BSVS = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath+'/'+ get_wrapper(module)
    BSVS = moduleList.getSynthBoundaryDependencies(module,'GIVEN_BSVS')
    # each submodel will have a generated BSV
    GEN_BSVS = moduleList.getSynthBoundaryDependencies(module,'GEN_BSVS')

    BSC =env['DEFS']['BSC']

    # this actually needs to be expanded 
  
    #  TMP_BSC_DIR = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' + env['DEFS']['TMP_BSC_DIR']

    TMP_BSC_DIR = env['DEFS']['TMP_BSC_DIR']
 
    ## We get surrogate bsvs from our child synth boundaries.
    synth_children = moduleList.getSynthBoundaryChildren(module)
    SUBDIRS = ''
    for child in synth_children:
      SUBDIRS += child.name + ' ' 

    SURROGATE_BSVS = transform_string_list(SUBDIRS, None, MODULE_PATH, '.bsv')

    ##
    ## Two views of the same directory hierarchy.  One view with paths all relative
    ## to the root of the build tree.  The other relative to this directory.  We
    ## need both because when scons passes over the files to compute dependence and
    ## build rules the working directory changes to the directory holding each
    ## scons file.
    ##
    ## When the rules are finally executed to build the target the directory is
    ## always the root of the build tree.
    ##

    ALL_DIRS_FROM_ROOT = env['DEFS']['ALL_HW_DIRS']
    # now that we build from base, there is no CWD_REL
    CWD_REL = ''#env['DEFS']['CWD_REL']

    ALL_BUILD_DIRS_FROM_ROOT = transform_string_list(ALL_DIRS_FROM_ROOT, ':', '', '/' + TMP_BSC_DIR)

    ALL_LIB_DIRS_FROM_ROOT = ALL_DIRS_FROM_ROOT + ':' + ALL_BUILD_DIRS_FROM_ROOT

    ALL_DIRS_FROM_CWD = ":".join([rebase_directory(x, CWD_REL) for x in clean_split(ALL_DIRS_FROM_ROOT)])
    ALL_BUILD_DIRS_FROM_CWD = transform_string_list(ALL_DIRS_FROM_CWD, ':', '', '/' + TMP_BSC_DIR)
    ALL_LIB_DIRS_FROM_CWD = ALL_DIRS_FROM_CWD + ':' + ALL_BUILD_DIRS_FROM_CWD

    ROOT_DIR_HW_INC = env['DEFS']['ROOT_DIR_HW_INC']
    ROOT_DIR_HW_INC_REL = rebase_directory(ROOT_DIR_HW_INC, CWD_REL)

    ##
    ## First compute dependence.  It runs pretty quickly so we do it every time
    ## without checking whether it is needed.  Knowing correct dependence before
    ## configuring the build rules makes the script simpler.
    ##
    DERIVED = ''
    if (SURROGATE_BSVS != ''):
      DERIVED = ' -derived "' + SURROGATE_BSVS + '"'
  
    s = os.system('leap-bsc-mkdepend -bdir ' + TMP_BSC_DIR + DERIVED + ' -p +:' + ROOT_DIR_HW_INC_REL + ':' + ROOT_DIR_HW_INC_REL + '/asim/provides:' + ALL_LIB_DIRS_FROM_CWD + ' ' + WRAPPER_BSVS + ' > ' + MODULE_PATH + '.depends-bsv')
    if (s & 0xffff) != 0:
      print 'Aborting due to dependence errors'
      sys.exit(1)

    if not os.path.isdir(TMP_BSC_DIR):
      os.mkdir(TMP_BSC_DIR)

    env.ParseDepends(MODULE_PATH +'.depends-bsv', must_exist = True)

    ##
    ## Cleaning?  There are a few somewhat unpredictable files generated by bsc
    ## depending on the source files.  Delete them here instead of parsing the
    ## source files and generating scons dependence rules.
    ##
    if env.GetOption('clean'):
      os.system('cd '+ MODULE_PATH + TMP_BSC_DIR + '; rm -f *.ba *.c *.h *.sched')


    # Builder for running just the compiler front end on a wrapper to find
    # the dangling connections.  This will then be passed to leap-connect
    # to determine the required connection array sizes.
    def compile_bsc_log(source, target, env, for_signature):
      ## Note -- we pipe through sed during the build to get rid of an extra
      ##         newline emitted by bsc's printType().  New compilers will make
      ##         this unnecessary
      cmd = compile_bo_bsc_base(target) + ' -KILLexpanded ' + str(source[0]) + \
            ' 2>&1 | sed \':S;/{[^}]*$/{N;bS};s/\\n/\\\\n/g\' | tee ' + str(target[0]) + ' ; test $${PIPESTATUS[0]} -eq 0'
      return cmd

    ##
    ## Every generated .bo file also has a generated .bi and .log file.  This is
    ## how scons learns about them.
    ##
    def emitter_bo(target, source, env):
      target.append(str(target[0]).replace('.bo', '.bi'))

      return target, source

    def compile_bo_bsc_base(target):
      bdir = os.path.dirname(str(target[0]))
      lib_dirs = bsc_bdir_prune(env,ALL_LIB_DIRS_FROM_ROOT, ':', bdir)
      return BSC + ' ' + self.BSC_FLAGS + ' -p +:' + \
           ROOT_DIR_HW_INC + ':' + ROOT_DIR_HW_INC + '/asim/provides:' + \
           lib_dirs + ':' + TMP_BSC_DIR + ' -bdir ' + bdir + \
           ' -vdir ' + bdir + ' -simdir ' + bdir + ' -info-dir ' + bdir

    def compile_bo(source, target, env, for_signature):
      cmd = compile_bo_bsc_base(target) + ' -D CONNECTION_SIZES_KNOWN ' + str(source[0])
      return cmd


    bsc = moduleList.env.Builder(generator = compile_bo, suffix = '.bo', src_suffix = '.bsv',
                emitter = emitter_bo)


    # This guy has to depend on children existing?
    # and requires a bash shell
    moduleList.env['SHELL'] = 'bash' # coerce commands to be spanwed under bash
    bsc_log = moduleList.env.Builder(generator = compile_bsc_log, suffix = '.log', src_suffix = '.bsv')      

    # SUBD method for building generated .bsv file.  Can't use automatic
    # suffix detection since source must be named explicitly.
    bsc_subd = moduleList.env.Builder(generator = compile_bo, emitter = emitter_bo)

    env.Append(BUILDERS = {'BSC' : bsc, 'BSC_LOG' : bsc_log, 'BSC_SUBD' : bsc_subd})


    moduleList.env.BuildDir(MODULE_PATH + TMP_BSC_DIR, '.', duplicate=0)

    bsc_builds = []
    for bsv in BSVS + GEN_BSVS:
      bsc_builds += env.BSC(MODULE_PATH + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + bsv)

    # we must making him depend on his children (NOT his children't children!)
    child_v = []
    for child in synth_children:
      child_v.append(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + get_child_v(child))



    wrapper_builds = []
    for bsv in  [get_wrapper(module)]:
      ##
      ## First pass just generates a log file to figure out cross synthesis
      ## boundary soft connection array sizes.
      ##
      # this is a little hosed.
    
      log = env.BSC_LOG(MODULE_PATH + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''),
                        MODULE_PATH + bsv)
      moduleList.env.Depends(log, child_v)
      # we should depend on subsidiary logs
      #moduleList.env.Depends(log, child_v)

      # Parse the log, generate a stub file
      stub_name = bsv.replace('.bsv', '_con_size.bsh')
      stub = env.Command(MODULE_PATH + stub_name, log, 'leap-connect --softservice --dynsize $SOURCE $TARGET')

      ##
      ## Now we are ready for the real build
      ##
      wrapper_bo = env.BSC(MODULE_PATH + TMP_BSC_DIR + '/' + bsv.replace('.bsv', ''), MODULE_PATH + bsv)
      moduleList.env.Depends(wrapper_bo, stub)

      ##
      ## The mk_<wrapper>.v file is really built by the Wrapper() builder
      ## above.  Unfortunately, SCons doesn't appear to like having rules
      ## refer to multiple targets of the same build.  The following hack
      ## appears to work:  a command with no action and the Precious() call
      ## to keep SCons from deleting the .v file.  I tried an Alias()
      ## first, but that didn't work.
      ##
      bld_v = env.Command(MODULE_PATH + TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.v'),
                          MODULE_PATH + TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                          '')
      env.Precious(bld_v)

      # we also generate all this synth boundary's GEN_VS
      gen_v = moduleList.getSynthBoundaryDependencies(module, 'GEN_VS')
      # dress them with the correct directory
      ext_gen_v = []
      for v in gen_v:
        ext_gen_v += [MODULE_PATH + TMP_BSC_DIR + '/' + v]

      if(BUILD_VERILOG == 1):
        module.moduleDependency['VERILOG'] += [bld_v] + [ext_gen_v]

      ##
      ## Do the same for .ba
      ##
      bld_ba = env.Command(MODULE_PATH + TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '.ba'),
                           MODULE_PATH + TMP_BSC_DIR + '/' + bsv.replace('.bsv', '.bo'),
                           '')
      env.Precious(bld_ba)
      print "Name: " + module.name
      # we also generate all this synth boundary's GEN_BAS
      gen_ba = moduleList.getSynthBoundaryDependencies(module, 'GEN_BAS')
      # dress them with the correct directory
      ext_gen_ba = []
      for ba in gen_ba:
        ext_gen_ba += [MODULE_PATH + TMP_BSC_DIR + '/' + ba]    
      module.moduleDependency['BA'] += [bld_ba] + [ext_gen_ba]


      ##
      ## Build the Xst black-box stub.
      ##
      bb = env.Command(MODULE_PATH + TMP_BSC_DIR + '/mk_' + bsv.replace('.bsv', '_stub.v'),
                       bld_v + bld_ba,
                       'leap-gen-black-box -nohash $SOURCE > $TARGET')

      # because I'm not sure that we guarantee the wrappers can only be imported
      # by parents, 
      moduleList.topModule.moduleDependency['VERILOG_STUB'] += [bb]

    ##
    ## Build subdirectories
    ##
    APM_FILE = env['DEFS']['APM_FILE']

    # the subdirs have already been built.  But we 
    # need to run leap connect on them 
    for child in synth_children:
      s = moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + module.buildPath + '/' + child.name +'.bsv'
      # Connection file derived from subdirectory build
      # need to point 
      # here we produce a link stub for the child directory.
      childModulePath =  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + child.buildPath + '/'
      sd = childModulePath + child.name +'.bsv'
      c = env.Command(s, # target
                      sd,
                      'leap-connect --softservice ' + APM_FILE + ' $TARGET')
      # Explicitly depend on the child build
      moduleList.env.Depends(c, child_v)

      # Build rule for the connection file
      env.BSC_SUBD(MODULE_PATH + TMP_BSC_DIR + '/' + child.name + '.bo', c)
 
    return wrapper_builds
