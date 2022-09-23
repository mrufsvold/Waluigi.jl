include("../src/Waluigi.jl")
using .Waluigi
@process struct GetADI
    output = DirectoryTarget("path/to/adi/dir")
end

function run(proc::GetADI)
    open(proc.output) do dir
        download_adi(dir)
    end
    complete(proc.output)
end

@process struct StackADI
    requires = GetADI
    output = FileTarget("path/to/adi.csv")
end

function run(proc::StackADI)
    df = DataFrame()
    for file in proc.requires.output.path
        df = vcat(df, DataFrame(file))
    end
    save(df,proc.output)
end


Base.@kwdef struct PipelineParams
    base_fp = "/path/to/data/dir"
end
params = PipelineParams()




function wal_require(proc::AbstractProcess, params)
end
wal_require(StackADI, params)
