module SPMD

export @spmd, spmdcall

using Distributed


"""
    SPMDResult

Contains a vector of futures.

Calling `getindex` on this will `fetch` the corresponding result.

`wait` will wait on all the futures.

`fetch` will return a vector of results.
"""
struct SPMDResult
    futures::Vector{Future}
end
SPMDResult() = Future[]

Base.length(res::SPMDResult) = length(res.futures)
Base.getindex(res::SPMDResult, i) = fetch(res.futures[i])


remoterefs(_) = nothing
remoterefs(spmd::SPMDResult) = spmd.futures


function getrref(arg, i)
    rrefs = remoterefs(arg)
    isnothing(rrefs) ? arg : rrefs[i]
end


struct Workers
    pids::Vector{Int}
end
Workers() = Workers(workers())

workers_from_objs(args...) = workers_from_rrefs(map(remoterefs, args)...)

workers_from_rrefs() = Workers()
workers_from_rrefs(::Nothing, args...) = workers_from_rrefs(args...)
function workers_from_rrefs(rrefs, args...)
    W = Workers(map(rref -> rref.where, rrefs))
    workers_from_rrefs(W, args...)
end
workers_from_rrefs(W::Workers) = W
workers_from_rrefs(W::Workers, ::Nothing, args...) =
    workers_from_rrefs(W, args...)
function workers_from_rrefs(W::Workers, rrefs, args...)
    all(zip(W.pids, rrefs)) do (pid, rref)
        pid == rref.where
    end || error("Incompatible distributed objects")
    workers_from_rrefs(W, args...)
end

"""
    spmdcall(fn, args...)

Call `fn(args...)` on each worker process, returning a `SPMDResult`. Each `arg` in `args`
will be sent to each process unless it is a _distributed object_ (i.e. it defines a
`SPMD.remoterefs(arg)` method, in which case it will receive the object underlying the
remote reference.

"""
spmdcall(fn, args...) = spmdcall(fn, workers_from_objs(args...), args...)

function spmdcall(fn, workers::Workers, args...)   
    rresult = map(enumerate(workers.pids)) do (i, pid)
        rargs = map(arg -> getrref(arg, i), args)
        remotecall(pid, rargs) do rargs
            fn(map(fetch, rargs)...)
        end
    end    
    return SPMDResult(rresult)
end



"""
    spmd_eval(m::Module, procs, ex)

Similar to `Distributed.remotecall_eval`, except (1) it doesn't synchronize, and (2) it
returns a [`SPMDResult`](@ref) object. Call `wait` or `fetch` on the `SPMDResult` object to
synchronize.
"""
function spmd_eval(m::Module, procs, ex)
    spmdcall(Core.eval, Workers(procs), m, ex)
end
function Base.wait(res::SPMDResult)
    local c_ex
    for f in res.futures
        try
            wait(f)
        catch e
            if !@isdefined(c_ex)
                c_ex = CompositeException()
            end
            push!(c_ex, e)
        end
    end
    if @isdefined(c_ex)
        throw(c_ex)
    end
    return nothing
end
function Base.fetch(res::SPMDResult)
    local c_ex
    results = map(res.futures) do f
        try
            fetch(f)
        catch e
            if !@isdefined(c_ex)
                c_ex = CompositeException()
            end
            push!(c_ex, e)
        end
    end
    if @isdefined(c_ex)
        throw(c_ex)
    end
    return results
end



"""
    @spmd [procs] expr

Evaluates `expr` on each process in `procs`, waiting until they complete, and return a
`SPMDResult` containing the futures.
"""
macro spmd(procs, ex)
    quote
        res = let ex = $(esc(Expr(:quote, ex))), procs = $(esc(procs))
            spmd_eval(Main, procs, ex)
        end
        wait(res)
        res
    end
end
macro spmd(ex)
    SPMD = @__MODULE__
    esc(:($SPMD.@spmd($SPMD.Distributed.workers(), $ex)))
end

function Base.show(io::IO, res::SPMDResult)
    limited = get(io, :limit, false)
    n = length(res.futures)
    if n == 0
        print(io, "0-element SPMDResult")
        return nothing
    end
    print(io, n, "-element SPMDResult:\n")
    if limited && n > 6
        for i = 1:4
            print_spmd(io, res.futures[i])
            print(io, '\n')
        end
        print(io," ⋮\n")
        print_spmd(io, res.futures[n-1])
        print(io, '\n')
        print_spmd(io, res.futures[n])
    else
        for i = 1:n-1
            print_spmd(io, res.futures[i])
            print(io, '\n')
        end
        print_spmd(io, res.futures[n])
    end
end

function print_spmd(io::IO, f::Future)
    pid = f.where
    fstr = remotecall_fetch(pid, f) do f
        sprint(show, fetch(f); context=:compact => true)
    end
    print(io, ' ', pid, "> ")
    print(io, fstr)
end


# prompt

end # module
