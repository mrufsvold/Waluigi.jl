module Waluigi

using Graphs
include("Targets.jl")
include("Processes.jl")
include("Pipeline.jl")

export @process
export Pipeline, run_pipeline
export DirectoryTarget, FileTarget


function run_pipeline(pipeline::Pipeline, first_proc::AbstractProcess)

    if is_complete(first_proc)
        println("$(typeof(first_proc)) is complete for the following params $(first_proc.params)")
        return :complete
    end

    length(pipeline.processes) == length(pipeline.process_graph) == 0 && error("Pipeline graph and processes must be empty.")

    # Add the process that will kick off the pipeline
    add_process!(pipeline, first_proc)
    # The recursively build the tree of all dependencies
    add_requirements!(analyze_requirements, 1)

end

end # module Waluigi
