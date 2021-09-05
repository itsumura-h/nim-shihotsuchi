import os, strformat, terminal, times, strutils
import utils

proc makeSeeder*(target:string, message:var string):int =
  # let now = now().format("yyyyMMddHHmmss")
  # var targetPath = &"{getCurrentDir()}/database/seeders/seeder{now}{target}.nim"
  var targetPath = &"{getCurrentDir()}/database/seeders/seeder_{target}.nim"

  if isFileExists(targetPath): return 0
  if isTargetContainSlash(target, "seeder file name"): return 0

  createDir(parentDir(targetPath))

#   var SEEDER = &"""
# import asyncdispatch, json
# import allographer/query_builder
# from ../../config/database import rdb


# proc seeder{now}{target}*() [[.async.]] =
#   if await(rdb.table("{target}").count()) == 0:
#     var data: seq[JsonNode]
#     await rdb.table("{target}").insert(data)
# """
  var SEEDER = &"""
import asyncdispatch, json
import allographer/query_builder
from ../../config/database import rdb


proc {target}*() [[.async.]] =
  if await(rdb.table("{target}").count()) == 0:
    var data: seq[JsonNode]
    await rdb.table("{target}").insert(data)
"""
  SEEDER = SEEDER.multiReplace(("[[", "{"), ("]]", "}"))

  var f = open(targetPath, fmWrite)
  f.write(SEEDER)
  f.close()

  message = &"Created seeder {targetPath}"
  styledWriteLine(stdout, fgGreen, bgDefault, message, resetStyle)

  # update seeder.nim
  targetPath = &"{getCurrentDir()}/database/seeders/seed.nim"
  f = open(targetPath, fmRead)
  let text = f.readAll()
  var textArr = text.splitLines()
  # get offset where column is empty string
  var offsets:seq[int]
  for i, row in textArr:
    if row == "":
      offsets.add(i)
  # insert array
  # textArr.insert(&"import seeder{now}{target}", offsets[0])
  # textArr.insert(&"  waitFor seeder{now}{target}()", offsets[1]+1)
  textArr.insert(&"import seeder_{target}", offsets[0])
  textArr.insert(&"  waitFor {target}()", offsets[1]+1)
  # write in file
  f = open(targetPath, fmWrite)
  defer: f.close()
  for i in 0..textArr.len-2:
    f.writeLine(textArr[i])
  message = &"Updated seed.nim"
  styledWriteLine(stdout, fgGreen, bgDefault, message, resetStyle)