import
  os, tables, times, re, strformat, osproc, terminal

let
  sleepTime = 1
  currentDir = getCurrentDir()

var
  files: Table[string, Time]
  isModified = false
  p: Process
  pid = 0

proc echoMsg(bg: BackgroundColor, msg: string) =
  styledEcho(fgBlack, bg, msg, resetStyle)

proc ctrlC() {.noconv.} =
  kill(p)
  discard execShellCmd(&"kill {pid}")
  echoMsg(bgGreen, "[SUCCESS] Stop dev server")
  quit 0
setControlCHook(ctrlC)

proc runCommand() =
  try:
    if pid > 0:
      discard execShellCmd(&"kill {pid}")
    discard tryRemoveFile("./main")
    if execShellCmd("nim c main") > 0:
      raise newException(Exception, "")
    echoMsg(bgGreen, "[SUCCESS] Start running dev server")
    p = startProcess("./main", currentDir, ["&"],
                    options={poStdErrToStdOut,poParentStreams})
    pid = p.processID()
  except:
    echoMsg(bgRed, "[FAILED] Build error")
    echo getCurrentExceptionMsg()
    quit 1

proc serve*() =
  runCommand()
  while true:
    sleep sleepTime * 1000
    for f in walkDirRec(currentDir, {pcFile}):
      if f.find(re"\.nim$") > -1:
        let modTime = getFileInfo(f).lastWriteTime
        if not files.hasKey(f):
          files[f] = modTime
          # debugEcho &"Skip {f} because of first checking"
          continue
        if files[f] == modTime:
          # debugEcho &"Skip {f} because of the file has not modified"
          continue
        # modified
        isModified = true
        files[f] = modTime
      
    if isModified:
      isModified = false
      runCommand()