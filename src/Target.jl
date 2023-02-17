using Random
using Serialization

"""
A target is a result side effect of a process; the things we're trying to make the a pipeline.

The interface for a target has the following functions:

is_complete(::Target) Returns a bool for if the target has been created
complete(::Target) Called to clean up the target (i.e. move from tmp_dir to final)
open(::Target) Called to access the target. Usually, this means returning the tmp field until
    the process is completed.

"""
abstract type AbstractTarget end

struct NoTarget <: AbstractTarget end 
Base.convert(::Type{AbstractTarget}, ::Nothing) = NoTarget()

struct LocalPathTarget <: AbstractTarget
    id::String
    path::String
end
LocalPathTarget(p) = LocalPathTarget(randomstring(10), p)

struct BinFileTarget <: AbstractTarget
    id::String
    dir::String
    fn::String
end
function BinFileTarget(dir::String, fn::String)
    fn = endswith(fn, ".bin") ? fn : fn * ".bin"
    return BinFileTarget(randstring(10), dir, fn)
end
iscomplete(t::BinFileTarget) = isfile(joinpath(t.dir, t.fn))
function store(t::BinFileTarget, data) 
    open(joinpath(t.dir, t.fn), "w") do io
        serialize(io, data)
    end
end
function retrieve(t::BinFileTarget)
    open(joinpath(t.dir, t.fn), "r") do io
        deserialize(io)
    end
end

