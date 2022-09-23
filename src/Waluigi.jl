module Waluigi

using Graphs
include("Targets.jl")
include("Processes.jl")
include("Pipeline.jl")

export @process
export Pipeline, run_pipeline
export DirectoryTarget, FileTarget

"""
run_pipeline(pipeline::Pipeline, first_proc::AbstractProcess)

Given a new pipeline and the final resulting process, recursively satisfy all
dependencies.
"""
function run_pipeline(pipeline::Pipeline, first_proc::AbstractProcess)
    # TODO make a Waluigid that serves a UI 
    # Have a worker check on pipeline status and update the graph of processes
    # Need to pass a ref to the pipeline for this 

    if is_complete(first_proc)
        println("$(typeof(first_proc)) is complete for the following params $(first_proc.params)")
        return :complete
    end

    length(pipeline.processes) == length(pipeline.process_graph) == 0 && error("Pipeline graph and processes must be empty.")

    # Add the process that will kick off the pipeline
    add_process!(pipeline, first_proc)
    # The recursively build the tree of all dependencies
    add_requirements!(analyze_requirements, 1)
    # Then execute them
    run_processes!(pipeline, 1)
end

end # module Waluigi
