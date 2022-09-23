using Random

"""
A target is a result side effect of a process; the things we're trying to make the a pipeline.

The interface for a target has the following functions:

is_complete(::Target) Returns a bool for if the target has been created
complete(::Target) Called to clean up the target (i.e. move from tmp_dir to final)
open(::Target) Called to access the target. Usually, this means returning the tmp field until
    the process is completed.

"""
abstract type AbstractTarget end

struct DirectoryTarget <: AbstractTarget
    tmp_fp::String
    fp::String
end
function DirectoryTarget(fp)
    fp_parts = splitpath(fp)
    fp_parts[end] = "waluigi_tmp_$(randstring(10))_$(fp_parts[end])"
    DirectoryTarget(joinpath(fp_parts), fp)
end
complete(t::DirectoryTarget) = mv(t.tmp_fp, t.fp)
is_complete(t::DirectoryTarget) = isdir(t.fp)
open(t::DirectoryTarget) = is_complete(t) ? t.tmp : t.fp

struct FileTarget <: AbstractTarget
    tmp_fp::String
    fp::String
end
function FileTarget(fp)
    fp_parts = splitpath(fp)
    fp_parts[end] = "waluigi_tmp_$(randstring(10))_$(fp_parts[end])"
    FileTarget(joinpath(fp_parts), fp)
end
complete(t::FileTarget) = mv(t.tmp_fp, t.fp)
is_complete(t::FileTarget) = isdir(t.fp)
function open(t::FileTarget, args...; kwargs...)
    # Check if output is complete, open the correct version of the file name
    is_complete(t) ? open(t.fp, args...; kwargs...) : open(t.tmp_fp, args...; kwargs...)
end
