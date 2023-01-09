using Random

"""
A target is a result side effect of a process; the things we're trying to make the a pipeline.

The interface for a target has the following functions:

is_complete(::Target) Returns a bool for if the target has been created
complete(::Target) Called to clean up the target (i.e. move from tmp_dir to final)
open(::Target) Called to access the target. Usually, this means returning the tmp field until
    the process is completed.

"""
abstract type AbstractTarget end

struct Target
    location
    config
    write_function
    read_function
end
write(t::Target, data) = t.write_function(data)
read(t::Target) = t.read_function()
