using Parquet2
using Tables


struct ParquetDirTarget <: Waluigi.AbstractTarget{Parquet2.Dataset}
    path::String
    write_kwargs
    read_kwargs
end
ParquetDirTarget(path; write_kwargs=(), read_kwargs=()) = ParquetDirTarget(path, write_kwargs, read_kwargs)
Waluigi.iscomplete(t::ParquetDirTarget) = isdir(t.path)
function Waluigi.store(t::ParquetDirTarget, data)
    isdir(t.path) && rm(t.path; force=true, recursive=true)
    mkdir(t.path)

    if Tables.istable(data)
        store_one(data, joinpath(t.path, "1.parq"), t.write_kwargs...)
    else
        store_many(data, t.path, t.kwargs...)
    end
    return nothing
end

function store_one(data, path, kwargs...)
    Parquet2.writefile(
        path, data;
        kwargs...
        )
end

function store_many(chunks, path, kwargs...) 
    for (i, chunk) in enumerate(chunks)
        Parquet2.writefile(
            joinpath(path, "$i.parq"), chunk;
            kwargs...
        )
    end
end
    
function Waluigi.retrieve(t::ParquetDirTarget)
    return Parquet2.Dataset(t.path; t.read_kwargs...)
end


