using Random

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
