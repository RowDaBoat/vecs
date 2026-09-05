import times, math, tables, random, os
import helpers/[benchmarks, churn_common, common]
import ../src/vecs

proc churnSpawn(w: var World): EntityId =
  w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)

proc churnDestroy(w: var World; entity: EntityId) =
  w.remove(entity, Immediate)

proc newChurnWorld(churned: bool): World =
  result = World()
  result.populateChurn(churned)

proc churnIterate(w: var World) =
  var q: Query[(Write[Position], Velocity)]
  for (pos, vel) in w.query(q):
    pos.x += vel.x
    pos.y += vel.y

# =========================
# Benchmarks
# =========================

proc runVecsBenchmarks(): BenchmarkSuite =
  var suite = initSuite("Vecs")

  # ------------------------------
  # Create entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "create entity",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
    ),
    (
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "create entity warmup",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]

      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)

      for e in ents:
        w.remove(e, Immediate)
    ),
    (
      for i in 0..<ENTITY_COUNT:
        ents[i] = w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Delete entity
  # ------------------------------
  suite.add benchmarkWithSetup(
    "delete entity",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)
    ),
    (
      for e in ents:
        w.remove(e, Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "delete entity warmup",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)

      for e in ents:
        w.remove(e, Immediate)

      for i in 0..<ENTITY_COUNT:
        ents[i] = w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)
    ),
    (
      for e in ents:
        w.remove(e, Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Add component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add component",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0),), Immediate)
    ),
    (
      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "add component warmup",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0),), Immediate)

      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)

      for e in ents:
        w.remove(e, Velocity, Immediate)
    ),
    (
      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Remove component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "remove component",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)
    ),
    (
      for e in ents:
        w.remove(e, Velocity, Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "remove component warmup",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)

      for e in ents:
        w.remove(e, Velocity, Immediate)

      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
    ),
    (
      for e in ents:
        w.remove(e, Velocity, Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Add + Remove component
  # ------------------------------
  suite.add benchmarkWithSetup(
    "add remove component",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0),), Immediate)
    ),
    (
      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
        w.remove(e, Velocity, Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  suite.add benchmarkWithSetup(
    "add remove component warmup",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0),), Immediate)

      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
        w.remove(e, Velocity, Immediate)
    ),
    (
      for e in ents:
        w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
        w.remove(e, Velocity, Immediate)
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Iteration
  # ------------------------------
  suite.add benchmarkWithSetup(
    "iteration",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      for i in 0..<ENTITY_COUNT:
        discard w.add((Position(x: 1.0, y: 1.0), Velocity(x: 1.0, y: 1.0)), Immediate)
      var q: Query[(Write[Position], Velocity)]

      for (pos, vel) in w.query(q):
        pos.x += vel.x
        pos.y += vel.y
    ),
    (
      for (pos, vel) in w.query(q):
        pos.x += vel.x
        pos.y += vel.y
    )
  )
  showDetailed(suite.benchmarks[^1])

  # ------------------------------
  # Read
  # ------------------------------
  var s = 0'f32
  suite.add benchmarkWithSetup(
    "read",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0),), Immediate)
    ),
    (
      for e in ents:
        s += w.read(e, Position).x
    )
  )
  showDetailed(suite.benchmarks[^1])
  blackBox(s)

  # ------------------------------
  # Write
  # ------------------------------
  suite.add benchmarkWithSetup(
    "write",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      var ents: seq[EntityId]
      for i in 0..<ENTITY_COUNT:
        ents.add w.add((Position(x: 1.0, y: 1.0),), Immediate)
    ),
    (
      for e in ents:
        for pos in w.write(e, Position):
          pos.x = s
          pos.y = s
    )
  )
  showDetailed(suite.benchmarks[^1])
  blackBox(s)

  var rng = initRand(42)
  suite.add benchmarkWithSetup(
    "heterogeneous iter",
    SAMPLE,
    WARMUP,
    (
      var w = World()
      for i in 0..<ENTITY_COUNT:
        let e = w.add((), Immediate)
        for j in 0..<10:
          if rng.rand(1.0) < SELECTION_THRESHOLD:
            case j
            of 0: w.add(e, Position(x: 1.0, y: 1.0), Immediate)
            of 1: w.add(e, Velocity(x: 1.0, y: 1.0), Immediate)
            of 2: w.add(e, Acceleration(x: 1.0, y: 1.0), Immediate)
            of 3: w.add(e, Rotation(angle: 0.5), Immediate)
            of 4: w.add(e, Scale(sx: 1.0, sy: 1.0), Immediate)
            of 5: w.add(e, Mass(value: 1.0), Immediate)
            of 6: w.add(e, Force(fx: 1.0, fy: 1.0), Immediate)
            of 7: w.add(e, Torque(value: 1.0), Immediate)
            of 8: w.add(e, Energy(value: 1.0), Immediate)
            of 9: w.add(e, Friction(coeff: 0.5), Immediate)
            else: discard
      var q: Query[(Write[Position], Velocity)]
      for (pos, vel) in w.query(q):
        pos.x += vel.x
        pos.y += vel.y
    ),
    (
      for (pos, vel) in w.query(q):
        pos.x += vel.x
        pos.y += vel.y
    )
  )
  showDetailed(suite.benchmarks[^1])

  addChurnRows(suite, "Vecs")

  return suite

if isMainModule:
  let outCsv = if paramCount() >= 1: paramStr(1) else: "benchs/vecs.csv"
  let baselineCsv = if paramCount() >= 2: paramStr(2) else: outCsv

  let suite = runVecsBenchmarks()
  suite.showSummary()

  if fileExists(baselineCsv):
    echo compareWithBaseline(suite, baselineCsv)
  else:
    echo "No baseline at ", baselineCsv, ", skipping comparison."

  suite.saveSummary(outCsv)
