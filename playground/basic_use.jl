include("../src/Waluigi.jl")
using .Waluigi
using HTTP

@process struct DownloadIrisData end
get_output(p::DownloadIrisData) = FileTarget(p.params.download_path)
function run(proc::DownloadIrisData)
    HTTP.request("GET", proc.params.iris_data_url) do r
        open(proc.output) do f
            write(f, r.body)
        end
    end
    complete(proc.output)
end

@process struct StackADI end
get_requirements(p::StackADI) = DownloadIrisData(p.params)
get_output(p::StackADI) = FileTarget(p.params["final_adi"])
function run(proc::StackADI)
    df = DataFrame()
    downloaded_adi_dir = proc.requires.output
    for file in get_path(downloaded_adi_dir)
        df = vcat(df, DataFrame(file))
    end
    save(df,proc.output)
end


Base.@kwdef struct PipelineParams
    iris_data_url = "https://archive.ics.uci.edu/ml/machine-learning-databases/iris/iris.data"
    download_path = "./test_download/iris.csv"
end

function try_pipeline()
    params = PipelineParams()
    pipeline = Waluigi.Pipeline(params)
    Waluigi.run_pipeline(pipeline, DownloadIrisData(;params = params))
end

try_pipeline()
