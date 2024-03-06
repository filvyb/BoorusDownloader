import httpclient, asyncdispatch, os
import db_connector/db_sqlite


var db: DbConn

proc initDB(dbpath: string) =
  if not fileExists(dbpath):
    db = open(dbpath, "", "", "")
    db.exec(sql"""CREATE TABLE posts (
                    id INTEGER PRIMARY KEY,
                    md5 TEXT,
                    file_ext TEXT,
                    tag_string TEXT,
                    tag_count_general INTEGER
                    )""")
  else:
    db = open(dbpath, "", "", "")
  
  db.exec(sql"PRAGMA journal_mode=WAL")



when isMainModule:
  initDB("boorufiles.sqlite")
