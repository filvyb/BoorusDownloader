# Package

version       = "0.1.0"
author        = "Filip Vybihal"
description   = "Downloder for multiple boorus saving files for training DeepDanbooru"
license       = "MIT"
srcDir        = "src"
bin           = @["BoorusDownloader"]


# Dependencies

requires "nim >= 2.0.0"
requires "db_connector"
requires "nimbooru >= 0.1.1"
requires "argparse >= 4.0.1"
