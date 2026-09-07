# ISC License
# Copyright (c) 2025 RowDaBoat
# `vecs` is a free open source ECS library for Nim.
import random
import benchmarks


const
  ChurnSeed = 90210
  ChurnEntityCount* = 1_000_000
  ChurnCapacity* = ChurnEntityCount * 2
  ChurnRoundCount = 10
  ChurnDivisor = 5
  ChurnPerRound = ChurnEntityCount div ChurnDivisor
  ChurnSamples = 20
  ChurnWarmup = 1


proc buildChurnSchedule(): seq[seq[int]] =
  var rng = initRand(ChurnSeed)
  var pool = newSeq[int](ChurnEntityCount)
  for i in 0 ..< ChurnEntityCount:
    pool[i] = i

  result = newSeq[seq[int]](ChurnRoundCount)
  for round in 0 ..< ChurnRoundCount:
    rng.shuffle(pool)
    result[round] = pool[0 ..< ChurnPerRound]


let churnSchedule* = buildChurnSchedule()


proc populateChurn*[W](world: var W; churned: bool) =
  mixin churnSpawn, churnDestroy

  var handles = newSeq[typeof(world.churnSpawn())](ChurnEntityCount)
  for i in 0 ..< ChurnEntityCount:
    handles[i] = world.churnSpawn()

  if churned:
    for round in churnSchedule:
      for idx in round:
        world.churnDestroy(handles[idx])
      for idx in round:
        handles[idx] = world.churnSpawn()


proc withFootprint(bench: Benchmark, bytes: float): Benchmark =
  result = bench
  result.mems = @[]
  for _ in 0 ..< max(1, bench.times.len):
    result.mems.add bytes
  finalize(result)


template addChurnRows*(suite: var BenchmarkSuite; suiteName: string) =
  mixin newChurnWorld, churnIterate

  block:
    let beforePristine = getOccupiedMem()
    var pristineWorld = newChurnWorld(false)
    let pristineBytes = (getOccupiedMem() - beforePristine).float

    let beforeChurned = getOccupiedMem()
    var churnedWorld = newChurnWorld(true)
    let churnedBytes = (getOccupiedMem() - beforeChurned).float

    var pristineBench = initBenchmark("pristine iter", ChurnSamples, ChurnWarmup)
    var churnedBench = initBenchmark("churn iter", ChurnSamples, ChurnWarmup)

    for _ in 0 ..< ChurnWarmup:
      pristineWorld.churnIterate()
      churnedWorld.churnIterate()

    for _ in 0 ..< ChurnSamples:
      let baseline = getOccupiedMem()
      measure(pristineBench, baseline):
        pristineWorld.churnIterate()
      measure(churnedBench, baseline):
        churnedWorld.churnIterate()

    finalize(pristineBench)
    finalize(churnedBench)

    suite.add withFootprint(pristineBench, pristineBytes)
    suite.add withFootprint(churnedBench, churnedBytes)
    showDetailed(suite.benchmarks[^2])
    showDetailed(suite.benchmarks[^1])
