import std/[ os,strformat ]

packageName   = "vecs"
version       = "0.0.1"
author        = "Row"
description   = "Vexel's ECS"
license       = "MIT"

srcDir        = "src"
binDir        = "bin"
skipFiles     = @[]

requires "nim >= 2.0.0"

task test, "Run the test suite":
  exec "nim r test/world.nim"
  exec "nim r test/queries.nim"
  exec "nim r test/id.nim"
  exec "nim r test/ecsseq.nim"

task docs, "Generate documentation":
  exec "nim doc --project --git.url:git@github.com:RowDaBoat/vecs.git --index:on --outdir:docs src/vecs.nim"
