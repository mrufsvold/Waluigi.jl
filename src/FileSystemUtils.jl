
function make_dir_and_parents(fp)
    fp_parts = splitpath(fp)
    for i in 1:(length(fp_parts))
        ancestor_fp = joinpath(fp_parts[begin:i])
        if ! isdir(ancestor_fp)
            mkdir(ancestor_fp)
        end
    end
    return nothing
end
