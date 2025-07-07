#run {
    set_build_options_dc(.{do_output=false});

    root_options := get_build_options();
    args := root_options.compile_time_command_line;

    set_working_directory(tprint("%/modules/LibreSSL", path_strip_filename(#filepath)));
    if !generate_libressl(args) {
        compiler_set_workspace_status(.FAILED);
        return;
    }

    set_working_directory(tprint("%/modules/zlib", path_strip_filename(#filepath)));
    if !generate_zlib(args) {
        compiler_set_workspace_status(.FAILED);
        return;
    }
}

#load "modules/LibreSSL/generate.jai";
#load "modules/zlib/generate.jai";

#import "Basic";
#import "Compiler";