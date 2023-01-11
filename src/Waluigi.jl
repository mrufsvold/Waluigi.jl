module Waluigi

export @Job, AbstractJob, get_dependencies, get_target, run_process, execute
include("FileSystemUtils.jl")
include("Job.jl")
include("Target.jl")

end # module Waluigi
