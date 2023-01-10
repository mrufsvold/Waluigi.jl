module Waluigi

export @Job, AbstractJob, parameters, parameter_types, dependencies, target, process
include("FileSystemUtils.jl")
include("Job.jl")
include("Target.jl")

end # module Waluigi
