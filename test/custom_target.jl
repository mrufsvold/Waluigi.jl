struct TextDirTarget <: Waluigi.AbstractTarget{String}
    path::String
    write_kwargs
    read_kwargs
end

TextDirTarget(path; write_kwargs=(), read_kwargs=()) = TextDirTarget(path, write_kwargs, read_kwargs)
Waluigi.is_complete(t::TextDirTarget) = isdir(t.path)

function Waluigi.store(t::TextDirTarget, data)
    isdir(t.path) && rm(t.path; force=true, recursive=true)
    mkdir(t.path)

    open(joinpath(t.path, "1.txt"), "w") do file
        write(file, data)
    end
    return nothing
end
    
function Waluigi.retrieve(t::TextDirTarget)
    return read(joinpath(t.path, "1.txt"), String)
end
