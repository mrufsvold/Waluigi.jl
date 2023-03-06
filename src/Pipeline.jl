include("PipelineInternals.jl")
"""
    run_pipeline(head_job)

Given an instantiated Job, satisfied all dependencies recursively and return the result of 
the final job. 
"""
function run_pipeline(@nospecialize(head_job), ignore_target=false; visualizer=false)
    if visualizer
        @info "Creating visualizer at http://localhost:8080/"
        start_viz()
    end

    @info "Initiating the pipeline"
    job_tree = JobTree(head_job)
    @info "Collected $(length(get_node_lookup(job_tree))) jobs to complete."
    root = get_root(job_tree)
    schedule_job(root; ignore_target)

    get_result(root)
end


function (@nospecialize(job::AbstractJob))(job_id::UInt64, ignore_target, @nospecialize(dependency_results...))
    @debug "Running spawned execution for job ID $job_id. Details: $job"
    target = get_target(job)
    
    if is_complete(target) && !ignore_target
        @debug "$job_id was already complete. Retrieving the target"
        data = retrieve(target)
        return ScheduledJob(job_id, target, data)
    end
    
    original_deps = get_dependencies(job)
    dependencies = replace_dep_job_with_result(original_deps, dependency_results)
    actual_result = run_process(job, dependencies, target)
    @debug "Ran dep, target, and process funcs against $job_id. Return type is $(typeof(actual_result))"
    data = if target isa NoTarget
        actual_result
    else
        @debug "Storing result for $job_id"
        store(target, actual_result)
        retrieve(target)
    end
    @debug "$job_id is complete."
    return ScheduledJob(job_id, target, data)
end

function replace_dep_job_with_result(dep_jobs::AbstractArray, dep_results)
    return ScheduledJob[
        dep_results[findfirst(res -> res.job_id == hash(job), dep_results) ]
        for job in dep_jobs]
end
function replace_dep_job_with_result(dep_jobs::AbstractDict, dep_results)
    return Dict{Symbol,ScheduledJob}(
        k => dep_results[findfirst(res -> res.job_id == hash(job), dep_results) ]
        for (k,job) in pairs(dep_jobs))
end

        



