# This file is a part of DataDeps.jl. License is MIT.

function handle_missing(datadep::DataDep, calling_filepath)::String
    save_dir = determine_save_path(datadep.name, calling_filepath)
    if env_bool("DATADEPS_DISABLE_DOWNLOAD")
        throw(DisabledError("DATADEPS_DISABLE_DOWNLOAD enviroment variable set. Can not trigger download."))
    end
    download(datadep, save_dir)
    save_dir
end

"""
    Base.download(
        datadep::DataDep,
        localpath;
        remotepath=datadep.remotepath,
        skip_checksum=false,
        i_accept_the_terms_of_use=nothing)

A method to download a datadep.
Normally, you do not have to download a data dependancy manually.
If you simply cause the string macro `datadep"DepName"`,
to be exectuted it will be downloaded if not already present.

Invoking this `download` method manually is normally for purposes of debugging,
As such it include a number of parameters that most people will not want to use.

 - `localpath`: this is the local path to save to.
 - `remotepath`: the remote path to fetch the data from, use this e.g. if you can't access the normal path where the data should be, but have an alternative.
 - `skip_checksum`: setting this to true causes the checksum to not be checked. Use this if the data has changed since the checksum was set in the registry, or for some reason you want to download different data.
 - `i_accept_the_terms_of_use`: use this to bypass the I agree to terms screen. Useful if you are scripting the whole process, or using annother system to get confirmation of acceptance.
     - For automation perposes you can set the enviroment variable `DATADEPS_ALWAYS_ACCEPT`
     - If not set, and if `DATADEPS_ALWAYS_ACCEPT` is not set, then the user will be prompted
     - Strictly speaking these are not always terms of use, it just refers to the message and permission to download.

 If you need more control than this, then your best bet is to construct a new DataDep object, based on the original,
 and then invoke download on that.
"""
function Base.download(
    datadep::DataDep,
    localdir;
    remotepath=datadep.remotepath,
    i_accept_the_terms_of_use = nothing,
    skip_checksum=false)

    accept_terms(datadep, localdir, remotepath, i_accept_the_terms_of_use)

    local fetched_path
    while true
        fetched_path = run_fetch(datadep.fetch_method, remotepath, localdir)
        if skip_checksum || checksum_pass(datadep.hash, fetched_path)
            break
        end
    end

    run_post_fetch(datadep.post_fetch_method, fetched_path)
end

"""
    run_fetch(fetch_method, remotepath, localdir)

executes the fetch_method on the given remote_path,
into the local directory and local paths.
Performs in (async) parallel if multiple paths are given
"""
function run_fetch(fetch_method, remotepath, localdir)
    mkpath(localdir)
    filename = get_filename(remotepath)
    localpath = joinpath(localdir, filename)
    #use the local folder and the remote filename
    fetch_method(remotepath, localpath)
    localpath
end

function run_fetch(fetch_method, remotepaths::Vector, localdir)
    asyncmap(rp->run_fetch(fetch_method, rp, localdir),  remotepaths)
end

function run_fetch(fetch_methods::Vector, remotepaths::Vector, localdir)
    asyncmap((meth, rp)->run_fetch(meth, rp, localdir),  fetch_method, remotepaths)
end


"""
    run_post_fetch(post_fetch_method, fetched_path)

executes the post_fetch_method on the given fetched path,
Performs in (async) parallel if multiple paths are given
"""
function run_post_fetch(post_fetch_method, fetched_path)
    cd(dirname(fetched_path)) do
        # Run things in the directory fetched from
        # useful if running `Cmds`
        post_fetch_method(fetched_path)
    end
end

function run_post_fetch(post_fetch_method, fetched_paths::Vector)
    asyncmap(fp->run_post_fetch(post_fetch_method, fp),  fetched_paths)
end

function run_post_fetch(post_fetch_methods::Vector, fetched_paths::Vector)
    asyncmap((meth, fp)->run_post_fetch(meth, fp),  post_fetch_methods, fetched_paths)
end



"""
    checksum_pass(hash, fetched_path)

Ensures the checksum passes, and handles the dialog with use user when it fails.
"""
function checksum_pass(hash, fetched_path)
    if !run_checksum(hash, fetched_path)
        warn("Hash failed on $(fetched_path)")
        reply = input_choice("Do you wish to Abort, Retry download or Ignore", 'a','r','i')
        if reply=='a'
            abort("Hash Failed, user elected not to retry")
        elseif reply=='r'
            return false
        end
    end
    true
end

##############################
# Term acceptance checking

"""
    accept_terms(datadep, localpath, remotepath, i_accept_the_terms_of_use)

Ensurses the user accepts the terms of use; otherwise errors out.
"""
function accept_terms(datadep::DataDep, localpath, remotepath, ::Void)
   if haskey(ENV, "DATADEPS_ALWAY_ACCEPT")
       warn("Environment variable \$DATADEPS_ALWAY_ACCEPT is deprecated. " *
            "Please use \$DATADEPS_ALWAYS_ACCEPT instead.")
   end
    if !(env_bool("DATADEPS_ALWAYS_ACCEPT") || env_bool("DATADEPS_ALWAY_ACCEPT"))
        response = check_if_accept_terms(datadep, localpath, remotepath)
        accept_terms(datadep, localpath, remotepath, response)
    else
        true
    end
end
function accept_terms(datadep::DataDep, localpath, remotepath, i_accept_the_terms_of_use::Bool)
    if !i_accept_the_terms_of_use
        abort("User declined to download $(datadep.name). Can not proceed without the data.")
    end
    true
end

function check_if_accept_terms(datadep::DataDep, localpath, remotepath)
    info("This program has requested access to the data dependency $(datadep.name).")
    info("which is not currently installed. It can be installed automatically, and you will not see this message again.")
    info("\n",datadep.extra_message,"\n\n")
    input_bool("Do you want to download the dataset from $remotepath to \"$localpath\"?")
end
