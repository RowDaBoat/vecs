# VEP-4 - Event Queue emit and collect
**Status:** Closed


## Problem
`vecs` has no mechanism for systems to communicate arbitrary typed events. Structural changes (add/remove) are detectable via `Not[T]` and `queryForRemoval`, but field-level changes cannot be queried for. An events API that can allow emitting and collecting events can help solve this.


## Solution
Add a typed event queue to `World` with two operations:

```nim
world.emit(myEvent(entityId))

for event in world.collect(MyEvent):
  process(event)
```

`emit` enqueues an event by type. `collect` yields all events of that type without draining, so multiple systems can listen to the same events within a frame. Queues are drained by `consolidate` at the frame boundary.
