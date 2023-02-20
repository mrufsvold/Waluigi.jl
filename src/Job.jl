# This is the internal Job structure
# TODO save the file and line number for the job definition so we can give clear debugging information
abstract type AbstractJob end

# This is what an executed Job will return
mutable struct ScheduledJob{T<:AbstractTarget, D}
    dependencies::Union{Vector{ScheduledJob}, Dict{Symbol, ScheduledJob}}
    target::T
    data::D
    function ScheduledJob(deps, target, data)
        returned_value_type = typeof(data)
        expected_type = return_type(target)
        if !(returned_value_type <: expected_type)
            throw(ArgumentError("Type of data must be a subtype of the target return type"))

        end
        return new{typeof(target), returned_value_type}(deps,target,data)
    end
end
return_type(sj::ScheduledJob) = return_type(sj.target)
Base.convert(::Type{ScheduledJob}, ::Nothing) = ScheduledJob([], NoTarget(), nothing)

# This is the interface for a Job. They dispatch on job type
get_dependencies(job) = nothing
get_target(job) = nothing
run_process(job, dependencies, target) = nothing

# Similar interface for ScheduledJob
get_dependencies(r::ScheduledJob) = r.dependencies
get_target(r::ScheduledJob) = r.target
get_result(r::ScheduledJob)= r.data

# This are the accepted versions of containers of jobs that the user can define for depenencies
const AcceptableDependencyContainers = Union{
    Vector{<:AbstractJob},
    AbstractDict{Symbol, <:AbstractJob},
}

"""
    @Job(job_description)

Constructs a new job based on a description. 

## Description Format
```juila
MyNewJob = @Job begin
    # Paramters are the input values for the job 
    parameters = (param1::String, param2::Int, param)
    
    # Dependencies list jobs that should be inputs to this job (Optional)
    # They can be created programmatically using parameters, and must return an
    # <:AbstractJob, AbstractArray{<:AbstractJob}, or AbstractDict{Symbol, <:AbstractJob}
    dependencies = [[SomeJob(i) for i in 1:param2]; AnotherJob("input")]
    
    # Target is an output location to cache the result. If the target exists, the job will
    # be skipped and the cached result will be returned (Optional).
    target = FileTarget(joinpath(snf_path, "raw_tables", "\$month.csv"))
    
    # The process function will be executed when the job is called.
    # All parameters, `dependencies`, and `target` are defined in this scope.
    process = begin
        dep1_data = dependencies[1]
        x = do_logic(dep1_data, param1)
        write(target, x)
        return x
    end
end
```
"""
macro Job(job_description)
    # This returns a Dict of job parameters and their values
    job_features = extract_job_features(job_description)
    
    job_name = job_features[:name]

    if job_name == Expr(:block, :nothing)
        return :(throw(ArgumentError("Job definitions require a `name` field but none was provided.")))
    end

    # Cleaning the parameters passed in
    raw_parameters = job_features[:parameters]
    # This is the list of parameters including type annotations if applicable
    parameter_list = raw_parameters isa Symbol ? (raw_parameters,) : raw_parameters.args
    # This is just the names
    parameter_names = [arg isa Symbol ? arg : arg.args[1] for arg in parameter_list]

    # get_dependencies need to return an `AcceptableDependencyContainers` and target needs to return an <:AbstractTarget
    # these functions append some protections and raise errors if the function returns an upexpected type
    dependency_func = add_get_dep_return_type_protection(job_features[:dependencies])
    target_func = add_get_target_return_type_protection(job_features[:target])
    
    dependency_ex = unpack_input_function(:get_dependencies, job_name, parameter_names, dependency_func)
    target_ex = unpack_input_function(:get_target, job_name, parameter_names, target_func)
    process_ex = unpack_input_function(:run_process, job_name, parameter_names, job_features[:process], (:dependencies, :target))
    
    struct_def = :(struct $job_name <: AbstractJob end)
    push!(struct_def.args[3].args, parameter_list...)

    # TODO: check if there is already a struct defined that is a complete match (name, fields, types)
    # if there is, then just emit the functions so since the user is probably just trying to 
    # edit the implementation of a funciton

    return quote
        $struct_def
        eval($(esc(dependency_ex)))
        eval($(esc(target_ex)))
        eval($(esc(process_ex)))
    end
end


function extract_job_features(job_description)
    job_features = Dict{Symbol,Any}()
    for element in job_description.args
        if element isa LineNumberNode
            continue
        end
        job_features[element.args[1]] = element.args[2]
    end

    for feature in (:name, :dependencies, :target, :process)
        if !(feature in keys(job_features))
            job_features[feature] = Expr(:block, :nothing)
        end
    end

    if !(:parameters in keys(job_features)) || job_features[:parameters] == :nothing
        job_features[:parameters] = :(())
    end

    return job_features
end


function unpack_input_function(function_name, job_name, parameter_names, function_body, additional_inputs=())
    return quote
        function Waluigi.$function_name(job::$job_name, $(additional_inputs...))
            let $((:($name = job.$name) for name in parameter_names)...)
                $function_body
            end
        end
    end
end



function add_get_dep_return_type_protection(func_block)
    return quote
        t = begin
            $func_block
        end
        corrected_deps = if t isa Nothing
            AbstractJob[]
        elseif t isa AbstractJob
            typeof(t)[t]
        elseif t isa Waluigi.AcceptableDependencyContainers
            t
        else
            throw(ArgumentError("""The dependencies definition in $(typeof(job)) returned a $(typeof(t)) \
which is not one of the accepted return types. It must return one of the following: \
<: AbstractJob, AbstractArray{<:AbstractJob}, Dict{Symbol, <:AbstractJob}"""))
        end
        return corrected_deps
    end
end


function add_get_target_return_type_protection(func_block)
    return quote
        t = begin
            $func_block
        end
        corrected_target = if t isa Nothing
            # TODO need to find a way to parameterize when no target is specified
            Waluigi.NoTarget{Any}()
        elseif t isa Waluigi.AbstractTarget
            t
        else
        throw(ArgumentError("""The target definition definition in $(typeof(job)) returned a $(typeof(t)), \
but target must return `nothing` or `<:AbstractTarget`"""))
        end
        return corrected_target
    end
end


function kickoff_dependencies(dep_jobs::T, ignore_target) where {T <: AbstractArray} 
    return ScheduledJob[execute(dep_job, ignore_target) for dep_job in dep_jobs]
end
function kickoff_dependencies(dep_jobs::T, ignore_target) where {T <: AbstractDict}
    jobs = Dict{Symbol,ScheduledJob}(
        name => execute(dep_job, ignore_target)
        for (name, dep_job) in pairs(dep_jobs)
    )
    return jobs
end

function execute(@nospecialize(job::J), ignore_target=false) where {J <: AbstractJob}
    dep_jobs = get_dependencies(job)
    dependencies = kickoff_dependencies(dep_jobs, ignore_target)

    # If the target is already complete, we can just return the previously calculated result
    target = get_target(job)
    if iscomplete(target) && !ignore_target
        data = retrieve(target)
        return ScheduledJob(dependencies, target, data)
    end

    actual_result = run_process(job, dependencies, target)
    
    data = if target isa NoTarget
        actual_result
    else
        store(target, actual_result)
        retrieve(target)
    end
    return ScheduledJob(dependencies, target, data)
end
