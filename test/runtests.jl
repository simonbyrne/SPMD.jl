using Distributed

addprocs(3, exeflags=`--project=$(Base.active_project())`)

using SPMD, Test

res = @spmd myid()
@test fetch(res) == collect(2:4)

@test sprint(show, res) == """
3-element SPMDResult:
 2> 2
 3> 3
 4> 4"""

y = 2
res = @spmd myid() + $y
@test fetch(res) == collect(4:6)
