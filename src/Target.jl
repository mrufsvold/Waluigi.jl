using Serialization

"""
A target is a result side effect of a process, the things we're trying to make with the pipeline.

The interface for a target has the following functions:

Waluigi.is_complete(<:AbstractTarget) Returns a bool for if the target has been created
Waluigi.store(<:AbstractTarget, data) Store the result of a Job to the target
Waluigi.retrieve(<:AbstractTarget) Reconstitute the data that was stored in a target

Targets are a parametric type. The type parameter refers to the return type of `retrieve`. 
This allows Waluigi to infer the type of the final result of a job before passing it on to the
next job. 
"""
abstract type AbstractTarget{T} end
return_type(::AbstractTarget{T}) where {T} = T
return_type(::Type{<:AbstractTarget{T}}) where {T} = T

struct NoTarget{T} <: AbstractTarget{T} end
NoTarget() = NoTarget{Any}()
Base.convert(::Type{AbstractTarget}, ::Nothing) = NoTarget{Any}()
is_complete(::NoTarget) = false

"""BinFileTarget(path)
A target that serializes the result of a Job and stores it in a .bin file at the designated path.
"""
struct BinFileTarget{T} <: AbstractTarget{T}
    path::String
    function BinFileTarget{T}(path) where {T}
        path = endswith(path, ".bin") ? path : path * ".bin"
        return new{T}(path)
    end
end
is_complete(t::BinFileTarget) = isfile(t.path)
function store(t::BinFileTarget, data) 
    open(t.path, "w") do io
        serialize(io, data)
    end
end
function retrieve(t::BinFileTarget{T}) where {T}
    open(t.path, "r") do io
        deserialize(io)::T
    end
end

