import algorithm, json, os, parseopt, posix, random, strutils, tables, uri

proc c_flock(fd, op: cint): cint {.importc: "flock", header: "<sys/file.h>".}
const LOCK_EX = 2.cint

const
  imageExts = [
    ".jpg", ".jpeg", ".png", ".webp", ".bmp", ".tif", ".tiff",
    ".gif", ".svg", ".svgz", ".avif", ".heif", ".heic", ".jxl"
  ]
  skipDirNames = [".git", ".hg", ".svn", "node_modules", ".Trash", "lost+found"]

proc cachePath(): string =
  let base =
    if existsEnv("XDG_CACHE_HOME") and getEnv("XDG_CACHE_HOME").len > 0:
      getEnv("XDG_CACHE_HOME")
    else:
      getHomeDir() / ".cache"
  let directory = base / "org.grey.simpleslideshow"
  createDir(directory)
  result = directory / "claims.json"

proc normalizeFolder(raw: string): string =
  var text = raw.strip()
  if text.startsWith("file:"):
    let parsed = parseUri(text)
    text = decodeUrl(parsed.path)
  result = expandTilde(text)

proc pathHasSkippedDir(path: string): bool =
  for part in path.split({'/'}):
    if part.len == 0 or part == "." or part == "..":
      continue
    if part in skipDirNames:
      return true
    if part.startsWith('.') and part != ".":
      return true
  result = false

proc isImage(path: string): bool =
  splitFile(path).ext.toLowerAscii in imageExts

proc collectImages(folders: seq[string]): seq[string] =
  var seen = initTable[string, bool]()
  for raw in folders:
    let root = normalizeFolder(raw)
    if not dirExists(root):
      continue
    for path in walkDirRec(root, yieldFilter = {pcFile}):
      if pathHasSkippedDir(parentDir(path)):
        continue
      if not isImage(path):
        continue
      let resolved =
        try:
          expandFilename(path)
        except OSError:
          path
      if not seen.hasKey(resolved):
        seen[resolved] = true
        result.add(resolved)

proc loadClaims(content: string): Table[string, string] =
  result = initTable[string, string]()
  if content.len == 0:
    return
  try:
    let node = parseJson(content)
    if node.kind != JObject:
      return
    for key, val in node.pairs:
      if val.kind == JString:
        result[key] = val.getStr
  except JsonParsingError:
    discard

proc claimsJson(claims: Table[string, string]): string =
  var node = newJObject()
  var keys: seq[string] = @[]
  for key in claims.keys:
    keys.add(key)
  algorithm.sort(keys)
  for key in keys:
    node[key] = %claims[key]
  pretty(node)

proc resolvePath(path: string): string =
  try:
    result = expandFilename(path)
  except OSError:
    result = path

proc pick(screen: string; screens: seq[string]; folders: seq[string];
          avoid: string): JsonNode =
  let images = collectImages(folders)
  var live: seq[string] = screens
  if screen notin live:
    live.add(screen)

  let stateFile = cachePath()
  if not fileExists(stateFile):
    writeFile(stateFile, "{}")

  var handle = open(stateFile, fmReadWriteExisting)
  let fd = cint(handle.getFileHandle)
  discard c_flock(fd, LOCK_EX)

  var claims = loadClaims(handle.readAll())
  var filtered = initTable[string, string]()
  for name, path in claims.pairs:
    if name in live:
      filtered[name] = path
  claims = filtered

  var taken = initTable[string, bool]()
  for name, path in claims.pairs:
    if name != screen and path.len > 0:
      taken[resolvePath(path)] = true

  var avoidSet = taken
  if avoid.len > 0:
    avoidSet[resolvePath(avoid)] = true

  var unique: seq[string] = @[]
  var pool: seq[string] = @[]
  for path in images:
    if not taken.hasKey(path):
      unique.add(path)
      if not avoidSet.hasKey(path):
        pool.add(path)

  if pool.len == 0:
    pool = unique
  if pool.len == 0:
    pool = images

  if pool.len == 0:
    discard ftruncate(fd, 0)
    handle.setFilePos(0)
    handle.write(claimsJson(claims))
    handle.flushFile()
    handle.close()
    return %*{
      "error": "no images found in the configured folders",
      "count": 0,
      "path": ""
    }

  let choice = pool[rand(pool.high)]
  claims[screen] = choice

  let body = claimsJson(claims)
  discard ftruncate(fd, 0)
  handle.setFilePos(0)
  handle.write(body)
  handle.flushFile()
  handle.close()

  result = %*{
    "path": choice,
    "count": images.len,
    "unique": unique.len,
    "screen": screen
  }

proc main() =
  randomize()
  var
    screen = ""
    screensRaw = ""
    folders: seq[string] = @[]
    avoid = ""

  proc takeVal(p: var OptParser; current: string): string =
    if current.len > 0:
      return current
    p.next()
    if p.kind == cmdArgument:
      return p.key
    result = ""

  var parser = initOptParser(shortNoVal = {}, longNoVal = newSeq[string]())
  while true:
    parser.next()
    case parser.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      case parser.key
      of "screen":
        screen = takeVal(parser, parser.val)
      of "screens":
        screensRaw = takeVal(parser, parser.val)
      of "folder":
        let folder = takeVal(parser, parser.val)
        if folder.len > 0:
          folders.add(folder)
      of "avoid":
        avoid = takeVal(parser, parser.val)
      else:
        discard
    of cmdArgument:
      discard

  if screen.len == 0:
    stderr.writeLine("missing --screen")
    quit(1)

  var screens: seq[string] = @[]
  for name in screensRaw.split(','):
    if name.len > 0:
      screens.add(name)

  let result = pick(screen, screens, folders, avoid)
  stdout.write($result)
  stdout.write("\n")
  if result.hasKey("error"):
    quit(1)

main()