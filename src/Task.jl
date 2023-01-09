# This is the internal Task structure
# TODO save the file and line number for the task definition so we can give clear debugging information
struct Task
    parameters::Tuple{Symbol}
    parameter_types::Tuple{Type}
    dependencies::Function
    target::Function
    process::Function
end

Base.@kwdef mutable struct Result
    parameters
    dependencies
    target
    data
end

dependencies(r::Result) = r.dependencies


"""
    @Task(task_description)

Constructs a new task based on a description. 

## Description Format
```juila
MyNewTask = @Task begin
    # Paramters are the input values for the task and it's dependencies
    # Type annotations will be enforced when the task is called, but cannot be
    # used for dispatch
    parameters = (param1::String, param2::Int)
    
    # Dependencies list tasks that should be inputs to this task (Optional)
    # They can be created programmatically using parameters
    dependencies = [[SomeTask(i) for i in 1:param2]; AnotherTask("input")]
    
    # Target is an output location to cache the result. If the target exists, the task will
    # be skipped and the cached result will be returned (Optional).
    target = FileTarget(joinpath(snf_path, "raw_tables", "\$month.csv"))
    
    # The process function will be executed when the task is called.
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
macro Task(task_description)
    task_features = extract_task_features(task_description)

    (param_list, param_type_list) = separate_type_annotations(task_features[:parameters])
    dependency_func = assure_result_is_array(task_features[:dependencies])
    task_definition = Expr(
        :call,
        :Task,
        :($param_list),
        :($param_type_list),
        make_anon_function_expr(dependency_func; kwargs=param_list),
        make_anon_function_expr(task_features[:target]; kwargs=param_list),
        make_anon_function_expr(task_features[:process]; args=(:dependencies, :target), kwargs=param_list)
    )
    return esc(task_definition)
end


function extract_task_features(task_description)
    task_features = Dict{Symbol,Union{Symbol,Expr}}()
    for element in task_description.args
        if element isa LineNumberNode
            continue
        end
        @assert element.head == Symbol("=") "No `=` operator found in task description for $element"
        task_features[element.args[1]] = element.args[2]
    end

    for feature in (:dependencies, :target, :process)
        if !(feature in keys(task_features))
            task_features[feature] = Expr(:block, :nothing)
        end
    end

    if !(:parameters in keys(task_features))
        task_features[:parameters] = :(())
    end

    return task_features
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


function assure_result_is_array(func_block)
    return Expr(
        :block,
        Expr(Symbol("="), :t, Expr(:block, func_block)),
        :(
            if !(t isa AbstractArray)
                return [t]
            end
        ),
        Expr(:return, :t)
    )
end


function separate_type_annotations(args_expr)
    arg_part_generator = (
        arg isa Symbol ?
        (arg, Any) :
        (arg.args[1], eval(arg.args[2]))
        for arg in args_expr.args)
    return (Tuple(arg[1] for arg in arg_part_generator), Tuple(arg[2] for arg in arg_part_generator))
end


function (task::Task)(; ignore_target=false, parameters...)
    needed_parameters = Dict(k => v for (k, v) in parameters if k in task.parameters)

    dep_tasks = task.dependencies(needed_parameters...)
    dependencies = if dep_tasks isa Nothing
        nothing
    else
        # TODO deps will be hard to find upstream if they're in a list like this
        # It would be helpful to names in a NamedTuple or Dict. But it's tough to imagine how to 
        # Create a name 
        dependencies = Vector(undef, length(dep_tasks))
        for (i, dep_task) in enumerate(dep_tasks)
            dependencies[i] = dep_task(; ignore_target=ignore_target, needed_parameters...)
        end
        dependencies
    end

    target = task.target(needed_parameters...)
    if iscomplete(target)
        data = read(target)
        return Result(dependencies, target, data)
    end

    data = task.process(dependencies, target; needed_parameters...)

    return Result(needed_parameters, dependencies, target, data)
end
