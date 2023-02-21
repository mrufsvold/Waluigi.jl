module Waluigi

using Dagger

export @Job, AbstractJob, get_dependencies, get_target, get_result, run_process, execute

include("Target.jl")
include("Job.jl")
include("Pipeline.jl")
end # module Waluigi
