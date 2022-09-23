module Waluigi

using Graphs
include("Targets.jl")
include("Processes.jl")
include("Pipeline.jl")

export @process
export Pipeline, run_pipeline
export AbstractTarget, DirectoryTarget, FileTarget

"""
run_pipeline(pipeline::Pipeline, final_process::AbstractProcess)

Given a new pipeline and the final resulting process, recursively satisfy all
dependencies.
"""
function run_pipeline(pipeline::Pipeline, final_process::AbstractProcess)
    # TODO make a Waluigid that serves a UI 
    # Have a worker check on pipeline status and update the graph of processes
    # Need to pass a ref to the pipeline for this 

    if is_complete(final_process)
        println("$(typeof(final_process)) is complete for the following params $(final_process.params)")
        return nothing
    end

    length(pipeline.processes) == length(pipeline.process_graph) == 0 && error("Pipeline graph and processes must be empty.")

    # Add the process that will kick off the pipeline
    add_process!(pipeline, final_process)
    # Recursively find and fullfill requirements until the first process is done.
    run_process!(pipeline)
    return nothing
end

end # module Waluigi
