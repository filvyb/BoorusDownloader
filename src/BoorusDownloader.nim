import httpclient, os, strutils, sequtils, std/enumutils
import waterpark/sqlite
import nimbooru
import argparse
import malebolgia

var dbpool: SqlitePool

proc parseEnumSymbol[T](s: string): T =
  var sym = s.toUpper
  for e in T.items:
    if e.symbolName.toUpper == sym:
      return e
  raise newException(ValueError, "Invalid enum symbol: " & s)

proc initDB(dbpath: string) =
  if not fileExists(dbpath):
    dbpool = newSqlitePool(10, dbpath)
    dbpool.withConnection conn:
      conn.exec(sql"""CREATE TABLE posts (
                      id INTEGER PRIMARY KEY,
                      md5 TEXT,
                      file_ext TEXT,
                      tag_string TEXT,
                      tag_count_general INTEGER,
                      booru TEXT
                      )""")
      
      conn.exec(sql"""CREATE INDEX md5_index ON posts (md5)""")
      conn.exec(sql"""CREATE INDEX md5_booru_index ON posts (md5, booru)""")
      conn.exec(sql"""CREATE INDEX id_booru_index ON posts (id, booru)""")
      conn.exec(sql"""CREATE INDEX id_md5_booru_index ON posts (id, md5, booru)""")
  else:
    dbpool = newSqlitePool(10, dbpath)
  dbpool.withConnection conn:
    conn.exec(sql"PRAGMA journal_mode=WAL")

proc insertImage(image: BooruImage, booru: string) =
  if image.hash == "":
    return

  var tags = image.tags.join(" ")
  var tmp = image.file_url.split(".")
  dbpool.withConnection conn:
    conn.exec(sql"INSERT INTO posts (md5, file_ext, tag_string, tag_count_general, booru) VALUES (?, ?, ?, ?, ?)", image.hash, tmp[^1], tags, image.tags.len, booru)

proc existsInDB(hash: string): bool =
  var res: seq[Row]
  dbpool.withConnection conn:
    res = conn.getAllRows(sql"SELECT id FROM posts WHERE md5 = ?", hash)
  return res.len > 0

proc downloadFile(client: HttpClient, image: BooruImage, folder_path: string): bool =
  if image.file_url == "" or image.hash == "":
    return false

  echo "Downloading ", image.file_url

  var filepath = folder_path
  if not dirExists(filepath):
    createDir(filepath)
  filepath = filepath / "images"
  if not dirExists(filepath):
    createDir(filepath)
  filepath = filepath / image.hash[0..1]
  if not dirExists(filepath):
    createDir(filepath)
  filepath = filepath / image.hash
  var tmp = image.file_url.split(".")
  filepath = filepath.addFileExt(tmp[^1])
  #var client = newHttpClient()
  try:
    client.downloadFile(image.file_url, filepath)
  except IOError:
    echo "Failed to download ", image.file_url
    return false
  return true

proc process_batch(images: seq[BooruImage], output: string, booru: string) =
  var client = newHttpClient()
  for i in images:
    if existsInDB(i.hash):
      echo "Already downloaded ", i.file_url
      continue
    if downloadFile(client, i, output):
      echo "Downloaded ", i.file_url
      insertImage(i, booru)

proc main_func(output: string, selected_boorus: seq[Boorus]) =
  initDB(output / "boorufiles.sqlite")

  var m = createMaster()
  m.awaitAll:
    for b in selected_boorus:
      var bc = initBooruClient(b)
      var images = bc.searchPosts()
      var page = 1
      while images.len > 0:
        m.spawn process_batch(images, output, $b)

        inc page
        images = bc.searchPosts(page = page)


when isMainModule:
  var p = newParser:
    option("-o", "--output", help="Output to this folder, defaults to MyDataset")
    option("-b", "--boorus", help="Type desired boorus from Nimbooru seperated by !")
    option("-cr", "--credentials", help="Type credentials for Boorus, in format apiKey;userId!apiKey;userId in order corresponding to Boorus")
    option("-vid", "--video", help="Download videos too")

  var dataset_path = "MyDataset"
  var video = false
  var selected_boorus: seq[Boorus]
  var creds: seq[(string, string)]

  try:
    var opts = p.parse(commandLineParams())
    if opts.output != "":
      dataset_path = opts.output
    if opts.video != "":
      video = true
    if opts.boorus == "":
      stderr.writeLine("You need to specify boorus you want to download")
      quit(1)
    var tmpseq = opts.boorus.split("!")
    for t in tmpseq:
      selected_boorus &= parseEnumSymbol[Boorus](t)

    if not dirExists(dataset_path):
      createDir(dataset_path)

  except ShortCircuit as e:
    if e.flag == "argparse_help":
      echo e.help
      quit(1)
  except UsageError as e:
    stderr.writeLine(e.msg)
    quit(1)

  main_func(dataset_path, selected_boorus)
