import httpclient, asyncdispatch, os, strutils, sequtils
import db_connector/db_sqlite
import nimbooru

var db: DbConn

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
  db.exec(sql"INSERT INTO posts (md5, file_ext, tag_string, tag_count_general, booru) VALUES (?, ?, ?, ?, ?)", image.hash, tmp[tmp.len - 1], tags, image.tags.len, booru)

proc existsInDB(hash: string): bool =
  var res = db.getAllRows(sql"SELECT id FROM posts WHERE md5 = ?", hash)
  return res.len > 0

proc downloadFile(image: BooruImage, folder_path: string): Future[bool] {.async.} =
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
  filepath = filepath.addFileExt(tmp[tmp.len - 1])
  var client = newAsyncHttpClient()
  try:
    await client.downloadFile(image.file_url, filepath)
  except IOError:
    echo "Failed to download ", image.file_url
    return false
  return true

proc main_func() {.async.} =
  initDB("MyDataset" / "boorufiles.sqlite")

  var b = initBooruClient(Danbooru)
  var images = await b.asyncSearchPosts()
  var page = 1
  while images.len > 0:
    for i in images:
      if existsInDB(i.hash):
        continue
      if await downloadFile(i, "MyDataset"):
        echo "Downloaded ", i.file_url
        insertImage(i, $Danbooru)

    inc page
    images = await b.asyncSearchPosts(page = page)



when isMainModule:
  waitFor main_func()
