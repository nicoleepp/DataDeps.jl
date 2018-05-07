# This file is a part of DataDeps.jl. License is MIT.

"""
    `datadep"Name"` or `datadep"Name/file"`

Use this just like you would a file path, except that you can refer by name to the datadep.
The name alone will resolve to the corresponding folder.
Even if that means it has to be downloaded first.
Adding a path within it functions as expected.
"""
macro datadep_str(namepath)
    quote
        resolve($(esc(namepath)), @__FILE__)
    end
end


"""
    resolve(datadep, inner_filepath, calling_filepath)

Returns a path to the folder containing the datadep.
Even if that means downloading the dependancy and putting it in there.

     - `inner_filepath` is the path to the file within the data dir
     - `calling_filepath` is a path to the file where this is being invoked from

This is basically the function the lives behind the string macro `datadep"DepName/inner_filepath"`.
"""
function resolve(datadep::AbstractDataDep, inner_filepath, calling_filepath)::String
    while true
        dirpath = _resolve(datadep, calling_filepath)
        filepath = joinpath(dirpath, inner_filepath)

        if can_read_file(filepath)
            return realpath(filepath) # resolve any symlinks for maximum compatibility with external applications
        else # Something has gone wrong
            warn("DataDep $(datadep.name) found at \"$(dirpath)\". But could not read file at \"$(filepath)\".")
            warn("Something has gone wrong. What would you like to do?")
            input_choice(
                ('A', "Abort -- this will error out",
                    ()->error("Aborted resolving data dependency, program could not continue.")),
                ('R', "Retry -- do this after fixing the problem outside of this script",
                    ()->nothing), # nothing to do
                ('X', "Remove directory and retry  -- will retrigger download if there isn't another copy elsewhere",
                    ()->rm(dirpath, force=true, recursive=true);
                )
            )
        end
    end
end

"""
Passing resolve a string rather than an actual datadep object works to look up
the data dep from the registry.
This is useful for progammatic downloading.
"""
function resolve(datadep_name::AbstractString, inner_filepath, calling_filepath)::String
    resolve(registry[datadep_name], inner_filepath, calling_filepath)
end

function resolve(namepath::AbstractString, calling_filepath=nothing)
    parts = splitpath(namepath)
    name = first(parts)
    inner_path = length(parts) > 1 ? joinpath(Iterators.drop(parts, 1)...) : ""
    resolve(name, inner_path, calling_filepath)
end


"The core of the resolve function without any user friendly file stuff, returns the directory"
function _resolve(datadep::AbstractDataDep, calling_filepath)::String
    lp = try_determine_load_path(datadep.name, calling_filepath)
    dirpath = if !isnull(lp)
        get(lp)
    else
        handle_missing(datadep, calling_filepath)
    end
end