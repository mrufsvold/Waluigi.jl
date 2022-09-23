include("../src/Waluigi.jl")
using .Waluigi

# I want @process to --
    # 1. add Base.@kwdef
    # 2. make subtype of AbstractProcess done
    # 3. define get_output() and get_requirements()
            # If reqs are not listed, just return Nothing
    # 4. Add a pipeline_params field if it doesn't have one


@process struct GetADI
    output = DirectoryTarget("path/to/adi/dir")
end

function run(proc::GetADI)
    open(proc.output.tmp) do dir
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
