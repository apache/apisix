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

def runcase(casedirpath):
    updatepip = "curl https://bootstrap.pypa.io/get-pip.py | python"
    requirements = "pip install -r %s/requirements.txt"%cur_file_dir()
    
    r_exc_case_cmd = subprocess.Popen(updatepip, stderr=subprocess.PIPE,shell=True)
    r_exc_case_cmd.wait()
    err = r_exc_case_cmd.stderr.read()

    r_exc_case_cmd = subprocess.Popen(requirements, stderr=subprocess.PIPE,shell=True)
    r_exc_case_cmd.wait()
    err = r_exc_case_cmd.stderr.read()

    #exc_case_cmd='pytest --force-flaky --max-runs=3 --no-flaky-report -q "%s" --html="%s/result.html" --self-contained-html > "%s/result.log"'%(casedirpath,casedirpath,casedirpath)
    #exc_case_cmd2='pytest --force-flaky --max-runs=3 --no-flaky-report -v -s "%s" > "%s/result.log"'%(casedirpath,casedirpath)
    #exc_case_cmd3='pytest --force-flaky --max-runs=3 --no-flaky-report -v -s "%s" '%(casedirpath)
    #r_exc_case_cmd = subprocess.Popen(exc_case_cmd3, stderr=subprocess.PIPE,shell=True)
    #r_exc_case_cmd.wait()
    #err = r_exc_case_cmd.stderr.read()

    #shutil.rmtree(cur_file_dir()+r'/.pytest_cache')
    #shutil.rmtree(casedirpath+r'/__pycache__')

casepath = cur_file_dir()+"/cases"
runcase(casepath)