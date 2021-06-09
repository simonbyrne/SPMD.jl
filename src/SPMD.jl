module SPMD

export @spmd

using Distributed


"""
    SPMDResult

Contains a vector of futures. Calling `getindex` on this will `fetch` the result.

"""
struct SPMDResult
    futures::Vector{Future}
end
Base.length(res::SPMDResult) = length(res.futures)
Base.getindex(res::SPMDResult, i) = fetch(res.futures[i])


function spmd_eval(m::Module, procs, ex)
    SPMDResult([remotecall(Core.eval, pid, m, ex) for pid in procs])
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

"""
    @spmd [procs] expr

Evaluates `expr` on each process in `procs`, waiting until they complete and return a
`SPMDResult` containing the futures.
"""
macro spmd(procs, ex)
    quote
        res = let ex = $(Expr(:quote, ex)), procs = $(esc(procs))
            spmd_eval(Main, procs, ex)
        end
        wait(res)
        res
    end
end
macro spmd(ex)
    :(@spmd(workers(), $ex))
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
