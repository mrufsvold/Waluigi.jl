"""
    run_pipeline(head_job)

Given an instantiated Job, satisfied all dependencies recursively and return the result of 
the final job. 
"""
function run_pipeline(head_job, ignore_target=false)
    # Jobs is a dict id => AbstractJob
    # dep_rel is a set{Tuple{job id, dep id, satisfied}
    # job status is a dict id => bool, true means ready to run 
    @info "Initiating the pipeline"
    (jobs, dependency_relations, initial_ready_jobs) = get_dependency_details(head_job)
    @info "Collected $(length(jobs)) jobs to complete. "
    results = Dict{UInt64, Union{Nothing, Dagger.EagerThunk}}(
        id => nothing
        for id in initial_ready_jobs
    )
    job_id = first(initial_ready_jobs)
    completed_all_jobs = false
    while !completed_all_jobs
        job_deps = [
            results[dep_pair[2]]
            for dep_pair in dependency_relations 
            if dep_pair[1] == job_id
        ]
        
        @debug "Spawning $(jobs[job_id])"
        results[job_id] = Dagger.@spawn execute(job_id, jobs[job_id], ignore_target, job_deps...)
        
        # Find upstream jobs and check if completing this job makes them ready for execution
        upstream_jobs = dependency_relations |>
                # get jobs that depend on the completed job
                ((dr) -> Iterators.filter((p) -> p[2] == job_id, dr)) .|>
                # Set "satisfied" field to true
                ((p) -> (delete!(dependency_relations, p); p)) .|>
                ((p) -> (push!(dependency_relations, (p[1], p[2], true)); p[1])) 
                
        for upstream in upstream_jobs
            is_unsatsifed_match_flag = Iterators.map(
                (rel) -> rel[1] == upstream && !rel[3], 
                dependency_relations
                )
            upstream_ready = !any(is_unsatsifed_match_flag)
            if upstream_ready
                results[upstream] = nothing
            end
        end

        job_id = findfirst(p -> p[2] === nothing, (p for p in pairs(results)))
        if job_id === nothing
            completed_all_jobs = true
        end
    end
    results[hash(head_job)]
end


function get_dependency_details(head_job)
    # The look up for the actual job objects
    jobs = Dict{UInt64, AbstractJob}()
    # Tracking if a job is ready to run
    ready_jobs = Set{UInt64}()
    dep_relations = Dict{Tuple{UInt64,UInt64,Bool}, Int}()
    traverse_dependencies!(head_job, jobs, dep_relations, ready_jobs)
    dep_relations = Set(keys(dep_relations))
    return (jobs = jobs, dependency_relations = dep_relations, ready_jobs = ready_jobs)
end

function traverse_dependencies!(job, jobs, dep_relations, ready_jobs, depth = 1)
    @debug "Maximum debug depth is 100. Currently at depth $depth"
    job_id = hash(job)
    if depth > 100
        error("Reached maximum depth. It's possible that there is a cycle in the dependencies but the parameters are different each time.")
    end
    # We need to get the dependencies as a vector (get values of dicts)
    dep_container = get_dependencies(job)
    dep_list = get_dependencies_list(dep_container)

    
    # Jobs with no dependencies are ready to run
    if isempty(dep_list)
        push!(ready_jobs, job_id)
    end

    jobs[job_id] = job

    # Go get grandchild dependency information
    for dep in dep_list
        dep_id = hash(dep)
        dependency = (job_id, dep_id, false)
        relation_occurances = get(dep_relations, dependency, 0) + 1
        if relation_occurances > 25
            check_for_circular_dependencies(jobs, keys(dep_relations))
        end
        dep_relations[(job_id, dep_id, false)] = relation_occurances
        traverse_dependencies!(dep, jobs, dep_relations, ready_jobs, depth + 1)
    end

    return nothing
end

get_dependencies_list(deps::AbstractDict{Symbol, AbstractJob}) = collect(values(deps))
get_dependencies_list(::Nothing) = AbstractJob[]
get_dependencies_list(deps) = deps

function check_for_circular_dependencies(jobs, dependency_relations)

    # SimpleDiGraph only uses OneTo Ints as IDs so we need a map back to job ids
    job_id_to_idx = Dict(
        job_id => i
        for (i, job_id) in enumerate(keys(jobs))
    )

    g = SimpleDiGraph(length(keys(jobs)))

    for (job_id, dep_id, _) in dependency_relations
        job_idx = job_id_to_idx[job_id]
        dep_idx = job_id_to_idx[dep_id]
        add_edge!(g, job_idx, dep_idx)
    end

    cycles = Graphs.simplecycles_iter(g)

    # Build a clean looking printout for the dependency cycle error
    if length(cycles) >= 1
        cycle_explanation = Vector{String}(undef, length(cycles) + sum(length.(cycles)))
        explain_idx = 1
        for (i, cycle) in enumerate(cycles)
            cycle_explanation[explain_idx] = "Cycle Number $i\n"
            explain_idx += 1
            for ci in eachindex(cycle)
                job_idx = cycle[ci]
                dep_idx = cycle[(ci)%length(cycle) + 1]
                job_id = findfirst(p -> p[2]==job_idx, (p for p in pairs(job_id_to_idx)))[1]
                dep_id = findfirst(p -> p[2]==dep_idx, (p for p in pairs(job_id_to_idx)))[1]
                job = jobs[job_id]
                dep = jobs[dep_id]
                cycle_explanation[explain_idx] = "\tDependency Pair$ci\n\t\t$job\n\t\t$dep\n"
                explain_idx += 1
            end
        end
        throw(InvalidStateException("The dependency tree contains cycles. Please resolve.\n" * foldl(*, cycle_explanation), :CyclicalDependency))
    end

end


id_to_name(hash_id) = Symbol("__$hash_id")


function execute(job_id::UInt64, job::AbstractJob, ignore_target, dependency_results...)
    @debug "Running spawned execution for job ID $job_id. Details: $job"
    target = get_target(job)
    
    if iscomplete(target) && !ignore_target
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

        



