# This is the internal Job structure
# TODO save the file and line number for the job definition so we can give clear debugging information
abstract type AbstractJob end


Base.@kwdef mutable struct ScheduledJob{T<:AbstractTarget}
    dependencies::Union{Vector{ScheduledJob}, Dict{Symbol, ScheduledJob}}
    target::T
    promise::Dagger.EagerThunk
end

Base.convert(::Type{ScheduledJob}, ::Nothing) = ScheduledJob([], NoTarget(), Dagger.spawn(() -> nothing))

get_dependencies(job) = nothing
get_target(job) = nothing
run_process(job, dependencies, target) = nothing

get_dependencies(r::ScheduledJob) = r.dependencies
get_target(r::ScheduledJob) = r.target
get_result(r::ScheduledJob) = fetch(r.promise)

const AcceptableDependencyContainers = Union{
    AbstractArray{<:AbstractJob},
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
    job_features = extract_job_features(job_description)
    
    job_name = job_features[:name]

    raw_parameters = job_features[:parameters]
    parameter_list = raw_parameters isa Symbol ? (raw_parameters,) : raw_parameters.args
    parameter_names = [arg isa Symbol ? arg : arg.args[1] for arg in parameter_list]

    dependency_func = add_get_dep_return_type_protection(job_features[:dependencies])
    target_func = add_get_target_return_type_protection(job_features[:target])

    dependency_ex = unpack_input_function(:get_dependencies, job_name, parameter_names, dependency_func)
    target_ex = unpack_input_function(:get_target, job_name, parameter_names, target_func)
    process_ex = unpack_input_function(:run_process, job_name, parameter_names, job_features[:process], (:dependencies, :target))

    struct_def = :(struct $job_name <: AbstractJob end)
    push!(struct_def.args[3].args, parameter_list...)

    return quote
        $struct_def
        eval($(esc(dependency_ex)))
        eval($(esc(target_ex)))
        eval($(esc(process_ex)))
    end
end


function extract_job_features(job_description)
    job_features = Dict{Symbol,Union{Symbol,Expr}}()
    for element in job_description.args
        if element isa LineNumberNode
            continue
        end
        @assert element.head == Symbol("=") "No `=` operator found in job description for $element"
        job_features[element.args[1]] = element.args[2]
    end

    for feature in (:dependencies, :target, :process)
        if !(feature in keys(job_features))
            job_features[feature] = Expr(:block, :nothing)
        end
    end

    if !(:parameters in keys(job_features)) || job_features[:parameters] == :nothing
        job_features[:parameters] = :(())
    end

    return job_features
end


function make_anon_function_expr(f; args=(), kwargs=nothing)
    sym_args = Any[Symbol(p) for p in args]
    if !(kwargs isa Nothing)
        pushfirst!(sym_args, Expr(:parameters, (Symbol(k) for k in kwargs)...))
    end
    return Expr(
        Symbol("->"),
        Expr(
            :tuple,
            sym_args...
        ),
        f
    )
end

function unpack_input_function(function_name, job_name, parameter_names, function_body, additional_inputs=())
    quote
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
        if t isa Nothing
            return AbstractJob[]
        elseif t isa AbstractJob
            return [t]
        elseif t isa Waluigi.AcceptableDependencyContainers
            return t
        end
        throw(ArgumentError("""The dependencies definition in $(typeof(job)) returned a $(typeof(t)) \
which is not one of the accepted return types. It must return one of the following: \
<: AbstractJob, AbstractArray{<:AbstractJob}, Dict{Symbol, <:AbstractJob}"""))
    end
end


function add_get_target_return_type_protection(func_block)
    return quote
        t = begin
            $func_block
        end
        if t isa Nothing
            return Waluigi.NoTarget()
        elseif t isa Waluigi.AbstractTarget
            return t
        end
        return t
        throw(ArgumentError("""The target definition definition in $(typeof(job)) returned a $(typeof(t)), \
but target must return `nothing` or `<:AbstractTarget`"""))
    end
end


function kickoff_dependencies(dep_jobs::T, ::Type, ignore_target) where {T <: AbstractArray} 
    return ScheduledJob[execute(dep_job, ignore_target) for dep_job in dep_jobs]
end
function kickoff_dependencies(dep_jobs::T, ::Type, ignore_target) where {T <: AbstractDict}
    jobs = Dict{Symbol,ScheduledJob}(
        name => execute(dep_job, ignore_target)
        for (name, dep_job) in pairs(dep_jobs)
    )
    return jobs
end
function kickoff_dependencies(::T, job_type::Type, ::Any) where {T}
    throw(ArgumentError("Job dependencies must be defined in an Array or a Dict. For $job_type, the depenencies field is returning a $T"))
end

function execute(job::J, ignore_target=false) where {J <: AbstractJob}
    # TODO deps will be hard to find upstream if they're in a list like this
    # It would be helpful to names in a NamedTuple or Dict. But it's tough to imagine how to 
    # Create a name 
    dep_jobs = get_dependencies(job)
    dependencies = kickoff_dependencies(dep_jobs, J, ignore_target)

    # If the target is already complete, we can just return the previously calculated result
    target = get_target(job)
    if !(target isa Nothing) && iscomplete(target)
        # TODO this should also be scheduled
        # And updated to whatever function I'm gonna use for target getting
        data = Dagger.@spawn retrieve(target)
        return ScheduledJob(dependencies, target, data)
    end


    # We should actually schedule this with dagger
    thunk = Dagger.@spawn run_process(job, dependencies, target)
    
    data = if target isa NoTarget
        thunk
    else
        store(target, fetch(thunk))
        Dagger.@spawn retrieve(target)
    end
    return ScheduledJob(dependencies, target, data)
end
