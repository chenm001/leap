
import os
import re
import sys
import string
from model import  *
from bsv_tool import *
from software_tool import *


class Bluesim():

  def __init__(self, moduleList):
    # get rid of this at some point - since we know we're in 
    # bluesim, we should be able to do the right thing.
    APM_NAME = moduleList.env['DEFS']['APM_NAME']
    BSC = moduleList.env['DEFS']['BSC']
    inc_paths = moduleList.swIncDir # we need to depend on libasim

    bsc_version = getBluespecVersion()

    ldflags = ''
    for ld_file in moduleList.getAllDependenciesWithPaths('GIVEN_BLUESIM_LDFLAGSS'):
      ldHandle = open(moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + ld_file, 'r')
      ldflags += ldHandle.read() + ' '    
        
    BSC_FLAGS_SIM = '-steps 10000000 +RTS -K1000M -RTS -keep-fires -aggressive-conditions -wait-for-license -no-show-method-conf -no-opt-bool -licenseWarning 7 -elab -show-schedule -l pthread ' + ldflags + ' '

    # Build in parallel.
    n_jobs = moduleList.env.GetOption('num_jobs')
    if (bsc_version >= 30006):
        BSC_FLAGS_SIM += '-parallel-sim-link ' + str(n_jobs) + ' '

    for path in inc_paths:
        BSC_FLAGS_SIM += '-I ' + path + ' '

    LDFLAGS = moduleList.env['DEFS']['LDFLAGS']

    TMP_BSC_DIR = moduleList.env['DEFS']['TMP_BSC_DIR']
    ROOT_WRAPPER_SYNTH_ID = 'mk_' + moduleList.env['DEFS']['ROOT_DIR_MODEL'] + '_Wrapper'

    ALL_DIRS_FROM_ROOT = moduleList.env['DEFS']['ALL_HW_DIRS']
    ALL_BUILD_DIRS_FROM_ROOT = transform_string_list(ALL_DIRS_FROM_ROOT, ':', '', '/' + TMP_BSC_DIR)
    ALL_LIB_DIRS_FROM_ROOT = ALL_DIRS_FROM_ROOT + ':' + ALL_BUILD_DIRS_FROM_ROOT
    
    bsc_sim_command = BSC + ' ' + BSC_FLAGS_SIM + ' ' + LDFLAGS + ' ' + ldflags + ' -o $TARGET'

    # Set MAKEFLAGS because Bluespec is going to invoke make on its own and
    # we don't want to pass on the current build's recursive flags.
    bsc_sim_command = 'env MAKEFLAGS="-j ' + str(n_jobs) + '" ' + bsc_sim_command


    if (bsc_version >= 13013):
        # 2008.01.A compiler allows us to pass C++ arguments.
        if (getDebug(moduleList)):
            bsc_sim_command += ' -Xc++ -O0'
        else:
            bsc_sim_command += ' -Xc++ -O1'

        # g++ 4.5.2 is complaining about overflowing the var tracking table

        if (getGccVersion() >= 40501):
             bsc_sim_command += ' -Xc++ -fno-var-tracking-assignments'

    defs = (host_defs()).split(" ")
    for definition in defs:
      bsc_sim_command += ' -Xc++ ' + definition + ' -Xc ' + definition


    def modify_path_bdpi(path):
        return  moduleList.env['DEFS']['ROOT_DIR_HW'] + '/' + path

    def modify_path_ba_local(path):
        return modify_path_ba(moduleList, path)

    LI_LINK_DIR = ""
    if(not (getFirstPassLIGraph()) is None):
      LI_LINK_DIR = get_build_path(moduleList, moduleList.topModule) + "/.li/:"

    bsc_sim_command += \
        ' -sim -e ' + ROOT_WRAPPER_SYNTH_ID + ' -p +:' + LI_LINK_DIR + ALL_LIB_DIRS_FROM_ROOT +' -simdir ' + \
        TMP_BSC_DIR + ' ' +\
        ' ' + moduleList.env['DEFS']['BDPI_CS']


    if (getBuildPipelineDebug(moduleList) != 0):
        print "BLUESIM DEPS: \n" 
        for ba in moduleList.getAllDependencies('BA'):
            print 'Bluesim BA dep: ' + str(ba) + '\n'

        for ba in map(modify_path_ba_local, moduleList.getAllDependenciesWithPaths('GIVEN_BAS')):
            print 'Bluesim GIVEN_BA dep: ' + str(ba) + '\n'

        for ba in map(modify_path_ba_local, moduleList.getAllDependenciesWithPaths('GEN_BAS')):
            print 'Bluesim GEN_BA dep: ' + str(ba) + '\n'

    sbin = moduleList.env.Command(
        TMP_BSC_DIR + '/' + APM_NAME + '_hw.exe',
        moduleList.getAllDependencies('BA') + 
        map(modify_path_ba_local, moduleList.getAllDependenciesWithPaths('GIVEN_BAS')) +
        map(modify_path_ba_local, moduleList.getAllDependenciesWithPaths('GEN_BAS')) +
        map(modify_path_bdpi, moduleList.getAllDependenciesWithPaths('GIVEN_BDPI_CS')) + 
        map(modify_path_bdpi, moduleList.getAllDependenciesWithPaths('GIVEN_BDPI_HS')),
        bsc_sim_command)

    if moduleList.env.GetOption('clean'):
        os.system('rm -rf .bsc')

    # If we have bsc data files, copy them over to the .bsc directory 
    if len(moduleList.getAllDependencies('GEN_VS'))> 0:
       Copy(TMP_BSC_DIR,  moduleList.getAllDependencies('GIVEN_DATAS')) 

    #
    # The final step must leave a few well known names:
    #   APM_NAME must be the software side, if there is one.  If there isn't, then
    #   it must be the Bluesim image.
    #
    if (getBuildPipelineDebug(moduleList) != 0):
        print "ModuleList desp : " + str(moduleList.swExe)

    exe = moduleList.env.Command(
        APM_NAME + '_hw.exe', 
        sbin,
        [ '@ln -fs ${SOURCE} ${TARGET}',
          '@ln -fs ${SOURCE}.so ${TARGET}.so',
          '@ln -fs ' + moduleList.swExeOrTarget + ' ' + APM_NAME,
          SCons.Script.Delete(APM_NAME + '_hw.vexe'),
          SCons.Script.Delete(APM_NAME + '_hw.errinfo') ])

    moduleList.topDependency = moduleList.topDependency + [exe] 
