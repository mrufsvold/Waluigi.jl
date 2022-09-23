"""
An AbstractProcess is the basic building block of the Waluigi Pipeline. A process has three
essential parts:
    1. Requirements: Processes on which the current process depends for input. If not included
    then the pipeline will assume there are no requirements.
    2. Output: The target(s) to be created by the process
    3. run(): A function that dispatches on the process type and executes the logic to create output

To construct your own process, use the @process macro in front of a struct definition like so:
```
@process struct ExampleProcess
    requires = PrereqProcess
    output = FileTarget("path/to/output.csv")
end
```
Then define a run function for this type.
```
function run(proc::ExampleProcess)
    open(proc.output.fp) do f
        write(f, "Output data to write to the file")
    end
end
```
"""
abstract type AbstractProcess end
@enum ProcessStatus Blocked Ready Complete Running Failed

macro process(expr) end

get_process_name(proc::AbstractProcess) = (name=typeof(proc), params=proc.params)
# Define functions for checking if a process, req, or output is complete
get_output(proc::AbstractProcess) = proc.output
struct NoRequirements end
function get_requirements(proc::AbstractProcess)
    if ! hasfield(proc, :requires) || proc.requires == []
        return NoRequirements()
    end
    return proc.requires isa Array ? proc.requires : [proc.requires]
end
is_complete(::NoRequirements) = true
is_complete(target_arr::Array{AbstractTarget}) = all(is_complete.(target_arr))
is_complete(proc::AbstractProcess) = is_complete(get_output(proc))
is_complete(procs::Array{AbstractProcess}) = all(is_complete.(procs))
