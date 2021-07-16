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
@test res[1] == 4
@test fetch(res) == collect(4:6)

res = spmd(+, res, 2)
@test fetch(res) == collect(6:8)

# functions need to be defined on all procs before use
@everywhere f(x) = x + 2 # we can't use @spmd as that won't define it on proc 1
res = spmd(f, res)
@test fetch(res) == collect(8:10)

# anonymous functions are serialized
res = spmd(res) do x 
    x+2
end
@test fetch(res) == collect(10:12)

g(x) = x + 2 # not defined on remote procs
err_res = spmd(g, res)
@test_throws RemoteException err_res[1]
@test_throws CompositeException fetch(err_res)

res1 = @spmd myid()
res2 = @spmd myid() + 1
res = spmd(+, res1, res2)
@test fetch(res) == collect(5:2:9)

resx = @spmd [2,3] myid()
@test_throws Exception spmd(+, res1, resx)
