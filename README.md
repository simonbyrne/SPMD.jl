# SPMD.jl

This package defines a `@spmd` macro which runs code on multiple processes. It is similar to [`Distributed.@everywhere`](https://docs.julialang.org/en/v1/stdlib/Distributed/#Distributed.@everywhere), except:
 - it only runs code on the worker processes by default, and
 - it returns a `SPMDResult` object which captures the `Future`s returned from each process.
 
 
 ```julia
 julia> using Distributed; addprocs(3)
3-element Vector{Int64}:
 2
 3
 4
 
julia> using SPMD

julia> @spmd myid()+10
3-element SPMDResult:
 2> 12
 3> 13
 4> 14
 ```
