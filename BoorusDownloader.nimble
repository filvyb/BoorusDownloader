# Package

version       = "1.0.0"
author        = "Filip Vybihal"
description   = "Downloder for multiple boorus saving files for training DeepDanbooru"
license       = "MIT"
srcDir        = "src"
bin           = @["BoorusDownloader"]


# Dependencies

requires "nim >= 2.0.0"
requires "nimbooru >= 0.1.2"
requires "argparse >= 4.0.1"
requires "waterpark >= 0.1.7"
requires "malebolgia#ed698c2"
