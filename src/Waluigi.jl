module Waluigi

using Dagger

export @Job, AbstractJob, get_dependencies, get_target, get_result, run_process, execute
include("FileSystemUtils.jl")
include("Target.jl")
include("Job.jl")

end # module Waluigi
