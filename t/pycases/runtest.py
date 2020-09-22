#!/usr/bin/env python
#-*- coding: utf-8 -*-

import random,subprocess,shutil
import time, datetime
import sys,os
import json
import re
import base64

def cur_file_dir():
    return os.path.split(os.path.realpath(__file__))[0]

def install_packages(casepath):
    new_packages=["pytest","pytest-html","futures"]
    for case_file_path in glob.glob(r'%s/*.py'%casepath):
        with open(case_file_path) as fh:
            rule = re.compile('from\s+(.+?)\s+import|import\s+(.*)') 
            result=rule.findall(fh.read())
            if len(result)>0:
                for i in range(len(result)):
                    for j in range(len(result[i])):
                        for k in result[i][j].split(","):
                            if k.strip()!='':
                                if k.strip().find('.')!=-1:
                                    new_packages.append(k.strip().split(".")[0])
                                else:
                                    new_packages.append(k.strip())
    new_packages=list(set(new_packages))
    # print new_packages
    self_packages=set()
    self_packages.update(sys.builtin_module_names)
    for dirName in os.listdir(r'%s\Lib'%py_path):         
        if os.path.isdir('%s\\Lib\\'%py_path+dirName):
            self_packages.add(dirName)
        elif dirName.endswith(".py"):
            self_packages.add(os.path.splitext(dirName)[0])

    cmd=r"pip list" # two format :  zope.interface (4.2.0)   or   altgraph                     0.16.1
    pipe1 = subprocess.Popen(cmd, shell=False, stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    content = pipe1.stdout.read()
    rule = re.compile('([^()\s]+)\s+\(?\d')
    # print rule.findall(content)
    self_packages.update(rule.findall(content))

    other=get_speciallibs()
    self_packages.update(other)
    for i in new_packages:
        if i not in self_packages and 'publicfunc' not in i:
            print u'%s发现新的依赖库%s，正在安装！'%(i,casepath)
            cmd=r"%s\Scripts\pip.exe install %s"%(py_path,i) # 用-U安装时可能会出错
            pipe = subprocess.Popen(cmd, shell=False, stdout=subprocess.PIPE)
            pipe.wait()
            # print pipe.read()
        # else:
            # print u"没有新的依赖库"

def runcase(casedirpath):

    updatepip = "curl https://bootstrap.pypa.io/get-pip.py | python"
    setupcmd = "pip install -r %s/requirements.txt"%cur_file_dir()
    exc_case_cmd='pytest --force-flaky --max-runs=3 --no-flaky-report -q "%s" --html="%s/result.html" --self-contained-html > "%s/result.log"'%(casedirpath,casedirpath,casedirpath)
    exc_case_cmd2='pytest --force-flaky --max-runs=3 --no-flaky-report -v -s "%s" > "%s/result.log"'%(casedirpath,casedirpath)

    #r_exc_case_cmd = subprocess.Popen(updatepip, stderr=subprocess.PIPE,shell=True)
    #r_exc_case_cmd.wait()
    #err = r_exc_case_cmd.stderr.read()
    #print(err)

    r_exc_case_cmd = subprocess.Popen(setupcmd, stderr=subprocess.PIPE,shell=True)
    r_exc_case_cmd.wait()
    err = r_exc_case_cmd.stderr.read()

    r_exc_case_cmd = subprocess.Popen(exc_case_cmd2, stderr=subprocess.PIPE,shell=True)
    r_exc_case_cmd.wait()
    err = r_exc_case_cmd.stderr.read()

    shutil.rmtree(cur_file_dir()+r'/.pytest_cache')
    shutil.rmtree(casedirpath+r'/__pycache__')



casepath = cur_file_dir()+"/cases"
runcase(casepath)