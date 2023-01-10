# This is the internal Job structure
# TODO save the file and line number for the job definition so we can give clear debugging information
abstract type AbstractJob end

parameters() = nothing
parameter_types() = missing
dependencies() = nothing
target() = nothing
process() = nothing

Base.@kwdef mutable struct Result
    parameters
    dependencies
    target
    data
end

dependencies(r::Result) = r.dependencies


"""
    @Job(job_description)

Constructs a new job based on a description. 

## Description Format
```juila
MyNewJob = @Job begin
    # Paramters are the input values for the job and it's dependencies
    # Type annotations will be enforced when the job is called, but cannot be
    # used for dispatch
    parameters = (param1::String, param2::Int)
    
    # Dependencies list jobs that should be inputs to this job (Optional)
    # They can be created programmatically using parameters
    dependencies = [[SomeJob(i) for i in 1:param2]; AnotherJob("input")]
    
    # Target is an output location to cache the result. If the target exists, the job will
    # be skipped and the cached result will be returned (Optional).
    target = FileTarget(joinpath(snf_path, "raw_tables", "\$month.csv"))
    
    # The process function will be executed when the job is called.
    # All parameters, `dependencies`, and `target` are defined in this scope.
    process = begin
        # Dependencies are not calculated until needed, call `collect()`
        # to get the data
        dep1_data = collect(dependencies[1])
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
    (param_list, param_type_list) = separate_type_annotations(job_features[:parameters])
    dependency_func = force_generator_or_array_result(job_features[:dependencies])

    return quote
        struct $job_name <: AbstractJob end
        eval(:(parameters(_::$$(esc(job_name))) = $$param_list))
        eval(:(parameter_types(_::$$(esc(job_name))) = $$param_type_list))
        eval(:(dependencies(_::$$(esc(job_name)); kwargs...) = $$dependency_func))
        eval(:(target(_::$$(esc(job_name)); kwargs...) = $$(job_features[:target])))
        eval(:(process(_::$$(esc(job_name)), dependencies, target; kwargs...) = $$(job_features[:target])))
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


function force_generator_or_array_result(func_block)
    return Expr(
        :block,
        Expr(Symbol("="), :t, Expr(:block, func_block)),
        :(
            if !(t isa Union{Base.Generator,AbstractArray})
                return [t]
            end
        ),
        Expr(:return, :t)
    )
end


function separate_type_annotations(args_expr)
    if args_expr isa Symbol
        return ((args_expr,), (Any,))
    end
    arg_part_generator = (
        arg isa Symbol ?
        (arg, Any) :
        (arg.args[1], eval(arg.args[2]))
        for arg in args_expr.args)
    return (Tuple(arg[1] for arg in arg_part_generator), Tuple(arg[2] for arg in arg_part_generator))
end


function (job::AbstractJob)(; ignore_target=false, params...)
    needed_parameters = Dict(k => v for (k, v) in params if k in parameters(job))
    for (type, (param_name, value)) in zip(parameter_types(job), pairs(needed_parameters))
        if !(value isa type)
            throw(MethodError(job, "$param_name must be of type $type, but $(typeof(value)) was passed."))
        end
    end
    dep_jobs = dependencies(job; needed_parameters...)
    dependencies = if (length(dep_jobs) > 0) && (first(dep_jobs) isa Nothing)
        nothing
    else
        # TODO deps will be hard to find upstream if they're in a list like this
        # It would be helpful to names in a NamedTuple or Dict. But it's tough to imagine how to 
        # Create a name 
        dependencies = Vector(undef, length(dep_jobs))
        for (i, dep_job) in enumerate(dep_jobs)
            dependencies[i] = dep_job(; ignore_target=ignore_target, needed_parameters...)
        end
        dependencies
    end

    target = target(job; needed_parameters...)
    if !(target isa Nothing) && iscomplete(target)
        data = read(target)
        return Result(dependencies, target, data)
    end

    data = process(job, dependencies, target; needed_parameters...)

    return Result(needed_parameters, dependencies, target, data)
end
