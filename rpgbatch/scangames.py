#!/usr/bin/env python
import os
import sys
import time
import cPickle as pickle
import numpy as np
from nohrio.ohrrpgce import *
from nohrio.dtypes import dt
from nohrio.wrappers import OhrData
from rpgbatch import RPGIterator, RPGInfo

if len(sys.argv) < 2:
    sys.exit("Specify .rpg files, .rpgdir directories, .zip files, or directories containing any of these as arguments.")
things = sys.argv[1:]

rpgidx = np.ndarray(shape = 0, dtype = RPGInfo)
gen = np.ndarray(shape = 0, dtype = dt['gen'])
mas = np.ndarray(shape = 0, dtype = dt['mas'])
fnt = np.ndarray(shape = 0, dtype = dt['fnt'])

data = []
withscripts = 0

def lumpbasename(name, rpg):
    name = os.path.basename(name)
    if name.startswith(rpg.archinym.prefix):
        name = name[len(rpg.archinym.prefix)+1:]
    return name

rpgs = RPGIterator(things)
for rpg, gameinfo, zipinfo in rpgs:
    # Let's fetch some useful data and store it
    if zipinfo:
        gameinfo.script = zipinfo.scripts
        if len(zipinfo.scripts):
            withscripts += 1
        print "scripts:", zipinfo.scripts
    else:
        gameinfo.scripts = []
    if rpg.lump_size('browse.txt'):
        browse = rpg.data('browse.txt')
        gameinfo.longname = browse.longname.value[0]
        gameinfo.aboutline = browse.about.value[0]
        del browse
    else:
        gameinfo.longname = ''
        gameinfo.aboutline = ''
    gameinfo.lumplist = [(lumpbasename(name, rpg), os.stat(name).st_size) for name in rpg.manifest]
    gameinfo.archinym = rpg.archinym.prefix
    gameinfo.arch_version = rpg.archinym.version
    rpgidx = np.append(rpgidx, gameinfo)

    # Fixed length lumps -- everything else is harder
    gen = np.append(gen, rpg.general)
    mas = np.append(mas, rpg.data('mas', shape = 1))  # Ignore overlong lumps
    fnt = np.append(fnt, rpg.data('fnt', shape = 1))

    # This is just a dumb example
    print "Processing RPG ", gameinfo.id
    print " > ", gameinfo.longname, " --- ", gameinfo.aboutline
    print "mod time =", time.ctime(gameinfo.mtime)
    print "maps =", int(rpg.general.maxmap) + 1
    print "format ver =", int(rpg.general.version)
    print "say size =", int(rpg.binsize.say)
    data.append((gameinfo.mtime, int(rpg.general.version), gameinfo.id))
rpgs.print_summary()
del rpgs

rpgidx = rpgidx.view(OhrData)
gen = gen.view(OhrData)
mas = mas.view(OhrData)
fnt = fnt.view(OhrData)

with open('gamedata.bin', 'wb') as f:
    pickle.dump({'rpgidx':rpgidx, 'gen':gen, 'mas':mas, 'fnt':fnt}, f)


# Continuing the dumb example
print withscripts, "games had script source"
print

data.sort()
for t, v, gameid in data:
    print time.ctime(t), " Format", v, gameid
