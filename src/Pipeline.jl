"""
    run_pipeline(head_job)

Given an instantiated Job, satisfied all dependencies recursively and return the result of 
the final job. 
"""
function run_pipeline(head_job)
    # Jobs is a dict id => AbstractJob
    # dep_rel is a set{Tuple{job id, dep id, satisfied}
    # job status is a dict id => bool, true means ready to run 
    (jobs, dependancy_relations, ready_jobs) = get_dependency_details(head_job)

    check_for_circular_dependencies(jobs, dependancy_relations)

    results = Dict{UInt64, Dagger.EagerThunk}()

    for job_id in ready_jobs
        job_deps = [
            results[dep_pair[2]]
            for dep_pair in dependancy_relations 
            if dep_pair[1] == job_id
        ]

        results[job_id] = Dagger.@spawn execute(job_id, jobs[job_id], job_deps...)
        
        # Find upstream jobs and check if completing this job makes them ready for execution
        upstream_jobs = dependancy_relations |>
                # get jobs that depend on the completed job
                ((dr) -> Iterators.filter((p) -> p[2] == job_id, dr)) .|>
                # Set "satisfied" field to true
                ((p) -> (delete!(dependancy_relations, p); p)) .|>
                ((p) -> (push!(dependancy_relations, (p[1], p[2], true)); p[1])) 
                
        for upstream in upstream_jobs
            is_unsatsifed_match_flag = Iterators.map(
                (rel) -> rel[1] == upstream && !rel[3], 
                dependancy_relations
                )
            upstream_ready = !any(is_unsatsifed_match_flag)
            if upstream_ready
                push!(ready_jobs, upstream)
            end
        end
    end

    results[hash(head_job)]
end


function get_dependency_details(head_job)
    # The look up for the actual job objects
    jobs = Dict{UInt64, AbstractJob}()
    # Tracking if a job is ready to run
    ready_jobs = Set{UInt64}()
    dep_relations = Set{Tuple{UInt64,UInt64,Bool}}()
    traverse_dependencies!(head_job, jobs, dep_relations, ready_jobs)
    return (jobs = jobs, dependancy_relations = dep_relations, ready_jobs = ready_jobs)
end

function traverse_dependencies!(job, jobs, dep_relations, ready_jobs)
    # We need to get the dependencies as a vector (get values of dicts)
    dep_container = get_dependencies(job)
    dep_list = get_dependencies_list(dep_container)

    job_id = hash(job)
    
    # Jobs with no dependencies are ready to run
    if isempty(dep_list)
        push!(ready_jobs, job_id)
    end

    jobs[job_id] = job

    # Go get grandchild dependancy information
    for dep in dep_list
        dep_id = traverse_dependencies!(dep, jobs, dep_relations, ready_jobs)
        push!(dep_relations, (job_id, dep_id, false))
    end

    return job_id
end

get_dependencies_list(deps::AbstractDict) = collect(values(deps))
get_dependencies_list(deps) = deps

function check_for_circular_dependencies(jobs, dependancy_relations)
    job_id_to_idx = Dict(
        job_id => i
        for (i, job_id) in enumerate(keys(jobs))
    )

    g = SimpleDiGraph{UInt64}(length(keys(jobs)))

    for (job_id, dep_id, _) in dependancy_relations
        job_idx = job_id_to_idx[job_id]
        dep_idx = job_id_to_idx[dep_id]
        add_edge!(g, job_idx, dep_idx)
    end

    cycles = Graphs.simplecycles_iter(g, 1)

    if length(cycles) > 1
        throw(ArgumentError("The dependency tree contains cycles. Please resolve."))
    end

end

id_to_name(hash_id) = Symbol("__$hash_id")


function execute(job_id::UInt64, job::AbstractJob, dependency_results...)
    target = get_target(job)
    
    if iscomplete(target) 
        data = retrieve(target)
        return ScheduledJob(job_id, target, data)
    end
    
    original_deps = get_dependencies(job)
    dependencies = replace_dep_job_with_result(original_deps, dependency_results)
    actual_result = run_process(job, dependencies, target)
    
    data = if target isa NoTarget
        actual_result
    else
        store(target, actual_result)
        retrieve(target)
    end
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

        



