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


"""BinFileTarget(path)
A target that serializes the result of a Job and stores it in a .bin file at the designated path.
"""
struct BinFileTarget <: AbstractTarget
    path::String
    BinFileTarget(path) = begin
        path = endswith(path, ".bin") ? path : path * ".bin"
        return new(path)
    end
end
iscomplete(t::BinFileTarget) = isfile(t.path)
function store(t::BinFileTarget, data) 
    open(t.path, "w") do io
        serialize(io, data)
    end
end
function retrieve(t::BinFileTarget)
    open(t.path, "r") do io
        deserialize(io)
    end
end

