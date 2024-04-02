import httpclient, asyncdispatch, os, strutils, sequtils, std/enumutils
import db_connector/db_sqlite
import nimbooru
import argparse

var db: DbConn

proc parseEnumSymbol[T](s: string): T =
  var sym = s.toUpper
  for e in T.items:
    if e.symbolName.toUpper == sym:
      return e
  raise newException(ValueError, "Invalid enum symbol: " & s)

proc initDB(dbpath: string) =
  if not fileExists(dbpath):
    db = open(dbpath, "", "", "")
    db.exec(sql"""CREATE TABLE posts (
                    id INTEGER PRIMARY KEY,
                    md5 TEXT,
                    file_ext TEXT,
                    tag_string TEXT,
                    tag_count_general INTEGER,
                    booru TEXT
                    )""")
    
    db.exec(sql"""CREATE INDEX md5_index ON posts (md5)""")
    db.exec(sql"""CREATE INDEX md5_booru_index ON posts (md5, booru)""")
    db.exec(sql"""CREATE INDEX id_booru_index ON posts (id, booru)""")
    db.exec(sql"""CREATE INDEX id_md5_booru_index ON posts (id, md5, booru)""")
  else:
    db = open(dbpath, "", "", "")
  
  db.exec(sql"PRAGMA journal_mode=WAL")

proc insertImage(image: BooruImage, booru: string) =
  if image.hash == "":
    return

  var tags = image.tags.join(" ")
  var tmp = image.file_url.split(".")
  db.exec(sql"INSERT INTO posts (md5, file_ext, tag_string, tag_count_general, booru) VALUES (?, ?, ?, ?, ?)", image.hash, tmp[^1], tags, image.tags.len, booru)

proc existsInDB(hash: string): bool =
  var res = db.getAllRows(sql"SELECT id FROM posts WHERE md5 = ?", hash)
  return res.len > 0

proc downloadFile(client: AsyncHttpClient, image: BooruImage, folder_path: string): Future[bool] {.async.} =
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
  #var client = newAsyncHttpClient()
  try:
    await client.downloadFile(image.file_url, filepath)
  except IOError:
    echo "Failed to download ", image.file_url
    return false
  return true

proc main_func(output: string, selected_boorus: seq[Boorus]) {.async.} =
  initDB(output / "boorufiles.sqlite")

  for b in selected_boorus:
    var bc = initBooruClient(b)
    var images = await bc.asyncSearchPosts()
    var page = 1
    var client = newAsyncHttpClient()
    while images.len > 0:
      for i in images:
        if existsInDB(i.hash):
          echo "Already downloaded ", i.file_url
          continue
        if await downloadFile(client, i, output):
          echo "Downloaded ", i.file_url
          insertImage(i, $b)

      inc page
      images = await bc.asyncSearchPosts(page = page)


when isMainModule:
  var p = newParser:
    option("-o", "--output", help="Output to this folder, defaults to MyDataset")
    option("-b", "--boorus", help="Type desired boorus from Nimbooru seperated by !")
    option("-cr", "--credentials", help="Type credentials for Boorus, in format apiKey;userId!apiKey;userId in order corresponding to Boorus")

  var dataset_path = "MyDataset"
  var selected_boorus: seq[Boorus]
  var creds: seq[(string, string)]

  try:
    var opts = p.parse(commandLineParams())
    if opts.output != "":
      dataset_path = opts.output
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

  waitFor main_func(dataset_path, selected_boorus)
