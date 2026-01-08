#
#            vecs - ECS library
#        (c) Copyright 2025 RowDaBoat
#

## `vecs` is a free open source ECS library for Nim.
import world, components, show, serialization
export world, components, show, serialization

import queries/[query, opNot, opWrite, opOpt]
export query, opNot, opWrite, opOpt
