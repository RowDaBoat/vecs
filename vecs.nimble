import std/[ os,strformat ]

packageName   = "vecs"
version       = "1.0.0"
author        = "Row"
description   = "Vexel's ECS"
license       = "MIT"

srcDir        = "src"
binDir        = "bin"
skipFiles     = @[]
bin           = @["vecs"]

requires "nim >= 2.0.0"
