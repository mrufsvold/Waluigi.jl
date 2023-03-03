module Waluigi

using Dagger
using Graphs
using Logging

export @Job, get_dependencies, get_target, get_result, execute, run_process

include("Target.jl")
include("Job.jl")
include("DaggerViz.jl")
include("Pipeline.jl")

end # module Waluigi
